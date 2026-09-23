# frozen_string_literal: true

# Lógica de saldo de IA por cuenta. Regla de negocio central:
#   - plan_budget_cents      → lo que da el plan; se RESTABLECE cada mes a su valor.
#   - purchased_budget_cents → comprado aparte; se ACUMULA (no se restablece).
#   - tope en el proveedor (max_budget) = (plan + purchased) / 100.
#
# Cada cambio: (1) actualiza el desglose en BD dentro de un lock, (2) registra el movimiento en
# el ledger append-only (idempotente), (3) sincroniza el tope con el proveedor. Nunca borra.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module AiProvider
    class BalanceService
      Result = Struct.new(:success, :provider_account, :error, keyword_init: true) do
        def success? = success
      end

      def initialize(account, client: nil)
        @account = account
        # Sin presupuesto de tiempo: corre en jobs, donde tardar no bloquea a ningún
        # usuario y cortar a medias dejaría el saldo desincronizado con el proveedor.
        @client = client || Jabvox::AiProvider::Client.new(budget_seconds: nil)
      end

      # Asigna/renueva el plan: fija el saldo del plan al presupuesto del plan y garantiza el
      # team en el proveedor. Idempotente por (cuenta, plan, periodo) para no duplicar al
      # renovar el mismo periodo. Llamar desde el aprovisionamiento tras pago/renovación.
      def apply_plan!(plan, reference: nil)
        plan_cents = plan&.ai_budget_cents_jabvox.to_i
        pa = provider_account
        idem = "plan_assign:#{@account.id}:#{plan&.id}:#{reference || JabvoxAiProviderAccount.current_period}"

        pa.with_lock do
          pa.plan_budget_cents_jabvox = plan_cents
          pa.last_reset_period_jabvox = JabvoxAiProviderAccount.current_period
          pa.save!
          record(pa, kind: 'plan_assign', amount_cents: plan_cents, plan_id: plan&.id,
                     reference: reference, idem: idem)
        end

        ensure_team_and_sync(pa)
        Result.new(success: true, provider_account: pa.reload)
      rescue StandardError => e
        fail_with(pa, e)
      end

      # Crea el team en el proveedor y lo liga a la cuenta MANUALMENTE, con un saldo inicial
      # opcional (en centavos) que va al saldo COMPRADO (no se restablece). Sirve para dar de
      # alta cualquier cuenta sin depender del plan. Idempotente: si ya tiene team, solo suma el
      # saldo inicial si se indica.
      def manual_setup!(initial_cents: 0, reference: nil)
        pa = provider_account
        reference ||= "manual:#{@account.id}:#{Time.current.to_i}"
        cents = initial_cents.to_i

        if cents.positive?
          idem = "adjustment:#{@account.id}:#{reference}"
          unless JabvoxAiBalanceMovement.exists?(idempotency_key_jabvox: idem)
            pa.with_lock do
              pa.purchased_budget_cents_jabvox = pa.purchased_budget_cents_jabvox.to_i + cents
              pa.save!
              record(pa, kind: 'adjustment', amount_cents: cents, reference: reference, idem: idem)
            end
          end
        end

        ensure_team_and_sync(pa, force: true)
        Result.new(success: true, provider_account: pa.reload)
      rescue StandardError => e
        fail_with(pa, e)
      end

      # Restablece el saldo del PLAN a su valor mensual (worker mensual). No toca lo comprado.
      # Idempotente por periodo: no restablece dos veces el mismo mes.
      def reset_monthly!(period: JabvoxAiProviderAccount.current_period)
        pa = provider_account
        return Result.new(success: true, provider_account: pa) if pa.last_reset_period_jabvox == period

        plan = @account.jabvox_plan
        plan_cents = plan&.ai_budget_cents_jabvox.to_i
        applied = false

        pa.with_lock do
          # Re-chequea dentro del lock (evita doble reset por jobs concurrentes). `next` en vez
          # de `return`: en una transacción, salir con return committea en Rails 7.2 en lugar de
          # respetar el bloque; next termina el bloque limpio sin aplicar el reset.
          next if pa.last_reset_period_jabvox == period

          pa.plan_budget_cents_jabvox = plan_cents
          pa.last_reset_period_jabvox = period
          pa.save!
          record(pa, kind: 'plan_reset', amount_cents: plan_cents, plan_id: plan&.id,
                     idem: "plan_reset:#{@account.id}:#{period}")
          applied = true
        end

        ensure_team_and_sync(pa) if applied
        Result.new(success: true, provider_account: pa.reload)
      rescue StandardError => e
        fail_with(pa, e)
      end

      # Recarga comprada aparte: SUMA al saldo comprado (que se acumula). Idempotente por
      # transacción (un webhook de pago reintentado no recarga dos veces).
      def purchase!(amount_cents:, reference:)
        raise ArgumentError, 'monto debe ser positivo' if amount_cents.to_i <= 0

        pa = provider_account
        idem = "purchase:#{@account.id}:#{reference}"

        # Si ya se registró esta transacción, no recargar de nuevo.
        return Result.new(success: true, provider_account: pa) if JabvoxAiBalanceMovement.exists?(idempotency_key_jabvox: idem)

        pa.with_lock do
          pa.purchased_budget_cents_jabvox = pa.purchased_budget_cents_jabvox.to_i + amount_cents.to_i
          pa.save!
          record(pa, kind: 'purchase', amount_cents: amount_cents.to_i, reference: reference, idem: idem)
        end

        ensure_team_and_sync(pa)
        Result.new(success: true, provider_account: pa.reload)
      rescue StandardError => e
        fail_with(pa, e)
      end

      # Sincroniza el gasto (spend) desde el proveedor a la caché local.
      def refresh_spend!
        pa = provider_account
        return Result.new(success: true, provider_account: pa) if pa.team_id_jabvox.blank?

        resp = @client.team_info(pa.team_id_jabvox)
        return Result.new(success: false, provider_account: pa, error: resp.error) unless resp.success?

        spend = resp.data.dig('team_info', 'spend') || 0
        pa.update!(cached_spend_jabvox: spend, spend_updated_at_jabvox: Time.current)
        Result.new(success: true, provider_account: pa)
      rescue StandardError => e
        fail_with(pa, e)
      end

      private

      def provider_account
        JabvoxAiProviderAccount.find_by(account_id: @account.id) ||
          JabvoxAiProviderAccount.create!(account_id: @account.id, origin_jabvox: 'jabvox')
      end

      # Garantiza que el team exista en el proveedor y sincroniza su tope con (plan+comprado).
      # Si el proveedor no está configurado, el MockAdapter lo simula (dev/test). Con force:true
      # crea el team aunque el saldo sea 0 (alta manual desde el Super Admin).
      def ensure_team_and_sync(pa, force: false) # rubocop:disable Naming/MethodParameterName
        return if !force && pa.total_budget_cents.zero? && pa.team_id_jabvox.blank?

        pa.team_id_jabvox.blank? ? create_remote_team(pa) : update_remote_budget(pa)
      end

      # models: [] = sin restricción de catálogo en LiteLLM. El límite real de la cuenta es el
      # presupuesto (max_budget), no la lista de modelos. Antes se enviaban aquí los MÓDULOS
      # del plan ('dialer', 'cdr'...), que LiteLLM interpreta como nombres de modelo
      # inexistentes y deja al team sin acceso a ninguno.
      def create_remote_team(pa) # rubocop:disable Naming/MethodParameterName
        resp = @client.create_team(
          alias_name: "crm-#{@account.id}", max_budget_usd: pa.total_budget_usd,
          models: [], metadata: { 'crm_id' => @account.id.to_s }
        )
        raise "no se pudo crear el team: #{resp.error}" unless resp.success?

        team_id = resp.data['team_id'] || resp.data.dig('team_info', 'team_id')
        pa.update!(team_id_jabvox: team_id, synced_at_jabvox: Time.current, last_error_jabvox: nil)
      end

      def update_remote_budget(pa) # rubocop:disable Naming/MethodParameterName
        resp = @client.update_team_budget(pa.team_id_jabvox, pa.total_budget_usd)
        raise "no se pudo actualizar el tope: #{resp.error}" unless resp.success?

        pa.update!(synced_at_jabvox: Time.current, last_error_jabvox: nil)
      end

      def record(pa, kind:, amount_cents:, idem:, plan_id: nil, reference: nil) # rubocop:disable Metrics/ParameterLists,Naming/MethodParameterName
        JabvoxAiBalanceMovement.record!(
          account: @account, kind: kind, amount_cents: amount_cents,
          plan_after: pa.plan_budget_cents_jabvox, purchased_after: pa.purchased_budget_cents_jabvox,
          plan_id: plan_id, reference: reference, idempotency_key: idem
        )
      end

      def fail_with(pa, error) # rubocop:disable Naming/MethodParameterName
        Rails.logger.error("[AiProvider::BalanceService] cuenta #{@account.id}: #{error.class}: #{error.message}")
        pa&.update_columns(last_error_jabvox: error.message.to_s[0, 300]) if pa&.persisted? # rubocop:disable Rails/SkipsModelValidations
        Result.new(success: false, provider_account: pa, error: error.message)
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
