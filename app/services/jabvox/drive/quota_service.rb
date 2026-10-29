# frozen_string_literal: true

# rubocop:disable Rails/SkipsModelValidations -- update_all es deliberado (ver nota abajo)

# Gestión de cuota del Drive por cuenta con RESERVAS ATÓMICAS.
#
# La cuota efectiva sale del plan: `account.storage_quota_bytes`
# (= effective_limit_for(:storage_gb).gigabytes). Cuota 0 = sin límite.
#
# La corrección frente a cargas concurrentes NO depende del lock de Redis (que es
# un "race dampener" no owner-checked): se apoya en la atomicidad de PostgreSQL.
# `reserve!` hace un UPDATE condicional que solo incrementa reserved_bytes si el
# resultado cabe en la cuota; si dos subidas compiten, una gana y la otra ve que
# ya no cabe. Flujo: reserve! -> subir a MinIO -> commit!(éxito) | release!(fallo).
#
# NOTA: `update_all` se usa DELIBERADAMENTE en los contadores. La corrección frente a
# carreras depende de un UPDATE atómico a nivel de BD; cargar el registro, validar y
# guardar reintroduciría la condición de carrera que este servicio existe para evitar.
# No hay validaciones de negocio en los contadores que deban correr por fila.
module Jabvox
  module Drive
    class QuotaService
      class QuotaExceededError < StandardError; end

      attr_reader :account

      def initialize(account)
        @account = account
      end

      # Cuota en bytes (0 = ilimitada). Reutiliza el entitlement del plan ya existente.
      def quota_bytes
        account.storage_quota_bytes.to_i
      end

      def unlimited?
        quota_bytes <= 0
      end

      def storage_account
        @storage_account ||= JabvoxDriveStorageAccount.find_or_create_by!(account_id: account.id)
      end

      def used_bytes
        storage_account.used_bytes.to_i
      end

      def reserved_bytes
        storage_account.reserved_bytes.to_i
      end

      def overflow_bytes
        storage_account.overflow_bytes.to_i
      end

      def committed_bytes
        used_bytes + reserved_bytes
      end

      def available_bytes
        return Float::INFINITY if unlimited?

        [quota_bytes - committed_bytes, 0].max
      end

      def fits?(bytes)
        unlimited? || committed_bytes + bytes.to_i <= quota_bytes
      end

      # Reserva atómica de `bytes`. Devuelve true si cabía (y los reserva), false si
      # no. Cuando no cabe, el llamador decide: subida normal -> rechazar; entrante
      # (WhatsApp) -> desviar a overflow.
      def reserve!(bytes)
        bytes = bytes.to_i
        return true if bytes <= 0

        ensure_row!

        if unlimited?
          bump!(reserved_bytes: bytes)
          return true
        end

        # UPDATE condicional atómico: solo reserva si used + reserved + bytes <= quota.
        affected = JabvoxDriveStorageAccount
                   .where(account_id: account.id)
                   .where('used_bytes + reserved_bytes + ? <= ?', bytes, quota_bytes)
                   .update_all(['reserved_bytes = reserved_bytes + ?, updated_at = now()', bytes])
        reload_storage_account
        affected.positive?
      end

      # Confirma una reserva: pasa `bytes` de reserved a used (la subida se completó).
      def commit!(bytes)
        bytes = bytes.to_i
        return if bytes <= 0

        ensure_row!

        JabvoxDriveStorageAccount
          .where(account_id: account.id)
          .update_all(['used_bytes = used_bytes + ?, reserved_bytes = GREATEST(reserved_bytes - ?, 0), updated_at = now()', bytes, bytes])
        reload_storage_account
      end

      # Libera una reserva que no se usó (la subida falló o se abortó).
      def release!(bytes)
        bytes = bytes.to_i
        return if bytes <= 0

        ensure_row!

        JabvoxDriveStorageAccount
          .where(account_id: account.id)
          .update_all(['reserved_bytes = GREATEST(reserved_bytes - ?, 0), updated_at = now()', bytes])
        reload_storage_account
      end

      # Resta de `used` al borrar un archivo del bucket principal.
      def decrement_used!(bytes)
        bytes = bytes.to_i
        return if bytes <= 0

        ensure_row!

        JabvoxDriveStorageAccount
          .where(account_id: account.id)
          .update_all(['used_bytes = GREATEST(used_bytes - ?, 0), updated_at = now()', bytes])
        reload_storage_account
      end

      def add_overflow!(bytes)
        bump!(overflow_bytes: bytes.to_i)
      end

      def remove_overflow!(bytes)
        bytes = bytes.to_i
        return if bytes <= 0

        ensure_row!

        JabvoxDriveStorageAccount
          .where(account_id: account.id)
          .update_all(['overflow_bytes = GREATEST(overflow_bytes - ?, 0), updated_at = now()', bytes])
        reload_storage_account
      end

      # Recalcula used/overflow desde la verdad (filas de jabvox_drive_files) y
      # pone reserved a 0 (no hay subidas en vuelo tras una reconciliación).
      def recalculate!
        ensure_row!
        # occupying_quota = activos + en papelera (NO purgados). La papelera SIGUE
        # ocupando espacio hasta que se elimine definitivamente (manual o a 7 días).
        scope = account.jabvox_drive_files.occupying_quota
        used = scope.where(bucket: JabvoxDriveFile::BUCKET_PRIMARY)
                    .where.not(status: :pending).sum(:byte_size)
        overflow = scope.where(bucket: JabvoxDriveFile::BUCKET_OVERFLOW).sum(:byte_size)
        storage_account.update!(used_bytes: used, overflow_bytes: overflow,
                                reserved_bytes: 0, last_reconciled_at: Time.current)
        storage_account
      end

      def summary
        {
          quota_bytes: unlimited? ? nil : quota_bytes,
          quota_gb: unlimited? ? nil : bytes_to_gb(quota_bytes),
          used_bytes: used_bytes,
          used_gb: bytes_to_gb(used_bytes),
          reserved_bytes: reserved_bytes,
          overflow_bytes: overflow_bytes,
          overflow_gb: bytes_to_gb(overflow_bytes),
          available_bytes: unlimited? ? nil : available_bytes,
          percent_used: unlimited? ? nil : ((committed_bytes.to_f / quota_bytes) * 100).round(2),
          unlimited: unlimited?
        }
      end

      private

      def ensure_row!
        storage_account
      end

      def bump!(reserved_bytes: 0, overflow_bytes: 0)
        ensure_row!
        JabvoxDriveStorageAccount
          .where(account_id: account.id)
          .update_all(['reserved_bytes = reserved_bytes + ?, overflow_bytes = overflow_bytes + ?, updated_at = now()',
                       reserved_bytes, overflow_bytes])
        reload_storage_account
      end

      def reload_storage_account
        @storage_account = JabvoxDriveStorageAccount.find_by(account_id: account.id)
      end

      def bytes_to_gb(bytes)
        (bytes.to_i.to_f / 1.gigabyte).round(4)
      end
    end
  end
end
# rubocop:enable Rails/SkipsModelValidations
