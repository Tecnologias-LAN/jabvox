# frozen_string_literal: true

# Sincronización LiteLLM → Jabvox. Trae TODOS los teams del proxy y los refleja en
# jabvox_ai_provider_accounts, de modo que el Super Admin vea en una sola pantalla lo que
# realmente existe en el proveedor.
#
# Reglas de mapeo (en orden de confianza, la primera que acierte gana):
#   1. Ya existe una fila local con ese team_id  → se actualiza (nunca se duplica).
#   2. metadata.crm_id apunta a una cuenta viva  → se liga automáticamente.
#   3. team_alias con forma "crm-<id>" y la cuenta existe → se liga automáticamente.
#   4. En cualquier otro caso → se importa como HUÉRFANO (account_id NULL) para que un
#      admin lo ligue a mano desde la UI. Nunca se adivina una cuenta.
#
# Lo que esta clase NO hace, deliberadamente:
#   - No borra nada en el proxy ni en Jabvox (la sincronización es aditiva).
#   - No pisa el desglose de saldo local (plan/comprado) con el max_budget remoto: ese
#     desglose es la fuente de verdad de Jabvox. El valor remoto se guarda aparte para
#     poder MOSTRAR la divergencia y que el admin decida.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    class SyncService
      # Tope de teams a procesar en una pasada: evita que un proxy con miles de teams
      # bloquee el request del Super Admin.
      MAX_TEAMS = 1000

      Result = Struct.new(:success, :imported, :updated, :linked, :orphans, :error,
                          keyword_init: true) do
        def success? = success

        def total = imported.to_i + updated.to_i
      end

      def initialize(client: nil)
        @client = client || Jabvox::AiProvider::Client.new
      end

      # Trae todo de LiteLLM y lo refleja localmente.
      def sync_all!
        resp = @client.list_teams
        return Result.new(success: false, error: resp.error) unless resp.success?

        teams = Jabvox::AiProvider::Client.normalize_team_list(resp.data).first(MAX_TEAMS)
        counters = sync_each(teams)

        Result.new(success: true, imported: counters[:imported], updated: counters[:updated],
                   linked: counters[:linked], orphans: JabvoxAiProviderAccount.orphans.count)
      rescue StandardError => e
        Rails.logger.error("[AiProvider::SyncService] #{e.class}: #{e.message}")
        Result.new(success: false, error: e.message)
      end

      # Liga un team huérfano (o cualquier fila) a una cuenta concreta. Valida que la cuenta
      # no tenga ya otro team, para no romper la relación 1:1.
      def link_to_account!(provider_account, account)
        raise ArgumentError, 'cuenta inválida' if account.nil?

        existing = JabvoxAiProviderAccount.where(account_id: account.id)
                                          .where.not(id: provider_account.id).first
        if existing
          raise ArgumentError,
                "La cuenta #{account.id} ya está ligada al team #{existing.team_id_jabvox.presence || '(sin team)'}. " \
                'Desligue ese primero.'
        end

        provider_account.update!(account_id: account.id)
        provider_account
      end

      # Desliga una fila de su cuenta y la deja como huérfana (el team sigue vivo en el proxy).
      def unlink!(provider_account)
        provider_account.update!(account_id: nil)
        provider_account
      end

      private

      # Procesa cada team aislando fallos: uno corrupto no aborta la sincronización completa.
      def sync_each(teams)
        counters = { imported: 0, updated: 0, linked: 0 }
        teams.each do |team|
          sync_team(team, counters)
        rescue StandardError => e
          Rails.logger.error("[AiProvider::SyncService] team #{team['team_id']}: #{e.class}: #{e.message}")
        end
        counters
      end

      def sync_team(team, counters)
        team_id = team['team_id'].to_s
        return if team_id.blank?

        record = JabvoxAiProviderAccount.find_by(team_id_jabvox: team_id)
        if record
          apply_remote_fields(record, team)
          record.save!
          counters[:updated] += 1
        else
          import_team(team_id, team, counters)
        end
      end

      def import_team(team_id, team, counters)
        account = mappable_account(team)
        record = JabvoxAiProviderAccount.new(
          team_id_jabvox: team_id, account_id: account&.id, origin_jabvox: 'litellm'
        )
        apply_remote_fields(record, team)
        record.save!
        counters[:linked] += 1 if account
        counters[:imported] += 1
      end

      # La cuenta inferida solo sirve si aún no tiene otra fila: así nunca se rompe el 1:1.
      def mappable_account(team)
        account = infer_account(team)
        return nil if account.nil? || JabvoxAiProviderAccount.exists?(account_id: account.id)

        account
      end

      # Copia al espejo local lo que reporta el proxy. NO toca el desglose plan/comprado.
      def apply_remote_fields(record, team)
        blocked = ActiveModel::Type::Boolean.new.cast(team['blocked']) || false
        record.assign_attributes(
          team_alias_jabvox: team['team_alias'].to_s.presence,
          remote_max_budget_jabvox: team['max_budget'],
          remote_blocked_jabvox: blocked,
          remote_models_jabvox: Array(team['models']).map(&:to_s),
          synced_at_jabvox: Time.current,
          last_error_jabvox: nil,
          # Refleja el bloqueo remoto en el estado local para que la UI no mienta.
          status_jabvox: blocked ? 'blocked' : 'active'
        )
        return unless team.key?('spend')

        record.cached_spend_jabvox = team['spend']
        record.spend_updated_at_jabvox = Time.current
      end

      # Deduce la cuenta de Jabvox a la que pertenece el team, sin adivinar: solo por
      # metadata.crm_id o por el alias canónico "crm-<id>".
      def infer_account(team)
        from_metadata(team) || from_alias(team)
      end

      def from_metadata(team)
        meta = team['metadata']
        return nil unless meta.is_a?(Hash)

        crm_id = meta['crm_id'] || meta['account_id']
        return nil if crm_id.blank?

        Account.find_by(id: crm_id.to_s[/\A\d+\z/])
      end

      def from_alias(team)
        match = team['team_alias'].to_s.match(/\Acrm-(\d+)\z/)
        return nil unless match

        Account.find_by(id: match[1])
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
