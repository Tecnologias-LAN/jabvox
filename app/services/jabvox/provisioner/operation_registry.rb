# frozen_string_literal: true

# Whitelist declarativa de TODAS las operaciones de la API Provisioner. Única fuente de
# verdad: una operación que no esté aquí no existe (anti-injection). Cada entrada declara el
# recurso y la acción (para el checklist de permisos) y el handler interno que la ejecuta.
#
# REGLAS DURAS:
#   - Solo view | edit | create. NUNCA delete/destroy (no hay ninguna entrada de borrado).
#   - Los recursos de solo lectura (pagos, transacciones, saldo, analytics DB) solo tienen
#     operaciones view.
#   - Ningún handler expone credenciales/secretos: los "view" devuelven resúmenes saneados.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Provisioner
    module OperationRegistry
      # operación => { resource:, action:, handler: }
      OPERATIONS = {
        # --- Cuentas ---
        'accounts.list' => { resource: 'accounts', action: 'view',   handler: :list_accounts },
        'accounts.get' => { resource: 'accounts', action: 'view',   handler: :get_account },
        'accounts.create' => { resource: 'accounts', action: 'create', handler: :create_account },
        'accounts.update' => { resource: 'accounts', action: 'edit',   handler: :update_account },

        # --- Usuarios ---
        'users.list' => { resource: 'users', action: 'view',   handler: :list_users },
        'users.get' => { resource: 'users', action: 'view',   handler: :get_user },
        'users.create' => { resource: 'users', action: 'create', handler: :create_user },
        'users.update' => { resource: 'users', action: 'edit',   handler: :update_user },

        # --- Módulos de la cuenta ---
        'account_modules.get' => { resource: 'account_modules', action: 'view', handler: :get_account_modules },
        'account_modules.set' => { resource: 'account_modules', action: 'edit', handler: :set_account_modules },

        # --- Planes ---
        'plans.list' => { resource: 'plans', action: 'view',   handler: :list_plans },
        'plans.get' => { resource: 'plans', action: 'view',   handler: :get_plan },
        'plans.create' => { resource: 'plans', action: 'create', handler: :create_plan },
        'plans.update' => { resource: 'plans', action: 'edit',   handler: :update_plan },
        'plans.set_status' => { resource: 'plans', action: 'edit',   handler: :set_plan_status },
        'plans.assign' => { resource: 'plans', action: 'edit',   handler: :assign_plan_to_account },

        # --- Solo lectura sensible ---
        'payment_gateways.list' => { resource: 'payment_gateways', action: 'view', handler: :list_payment_gateways },
        'transactions.list' => { resource: 'transactions', action: 'view', handler: :list_transactions },
        'transactions.get' => { resource: 'transactions', action: 'view', handler: :get_transaction },
        'limits.get' => { resource: 'limits', action: 'view', handler: :get_limits },
        'ip_whitelists.list' => { resource: 'ip_whitelists', action: 'view', handler: :list_ip_whitelists },
        'saldo.get' => { resource: 'saldo', action: 'view', handler: :get_saldo },
        'analytics_data_sources.list' => { resource: 'analytics_data_sources', action: 'view', handler: :list_data_sources },

        # --- Límites (edición permitida: no es credencial) ---
        'limits.set' => { resource: 'limits', action: 'edit', handler: :set_limits },

        # --- IP whitelist (gestión, no credencial) ---
        'ip_whitelists.create' => { resource: 'ip_whitelists', action: 'create', handler: :create_ip_whitelist },
        'ip_whitelists.set_active' => { resource: 'ip_whitelists', action: 'edit', handler: :set_ip_whitelist_active },

        # --- Softphone: extensiones + habilitar/deshabilitar ---
        'softphone.get' => { resource: 'softphone', action: 'view',   handler: :get_softphone },
        'softphone.create_extension' => { resource: 'softphone', action: 'create', handler: :create_extension },
        'softphone.set_enabled' => { resource: 'softphone', action: 'edit',   handler: :set_softphone_enabled },

        # --- Tokens de acción de los Hermes de la cuenta (para ligarlos) ---
        'hermes_tokens.list' => { resource: 'hermes_tokens', action: 'view', handler: :list_hermes_tokens },

        # --- Leads (lectura + import/export) ---
        'leads.list' => { resource: 'leads', action: 'view',   handler: :list_leads },
        'leads.import_sources' => { resource: 'leads', action: 'view',   handler: :list_lead_import_sources },
        'leads.trigger_import' => { resource: 'leads', action: 'edit',   handler: :trigger_lead_import },
        'leads.export_targets' => { resource: 'leads', action: 'view',   handler: :list_lead_export_targets },

        # --- Proveedor de IA (saldos por cuenta) ---
        # list: ver qué cuentas están conectadas (con team) o sin conectar.
        'ai_provider.list' => { resource: 'ai_provider', action: 'view',   handler: :ai_provider_list },
        'ai_provider.get' => { resource: 'ai_provider', action: 'view',   handler: :ai_provider_get },
        # setup: crea el team en el proveedor y lo asigna a la cuenta (aplica el saldo del plan).
        'ai_provider.setup' => { resource: 'ai_provider', action: 'create', handler: :ai_provider_setup },
        # create_key: crea el PRIMER virtual key del team de la cuenta.
        'ai_provider.create_key' => { resource: 'ai_provider', action: 'create', handler: :ai_provider_create_key },
        # recharge: suma saldo comprado aparte (se acumula).
        'ai_provider.recharge' => { resource: 'ai_provider', action: 'edit', handler: :ai_provider_recharge },
        # manual_setup: crea el team y lo liga SIN exigir plan (equivale a la pestana "Por cuenta").
        'ai_provider.manual_setup' => { resource: 'ai_provider', action: 'create', handler: :ai_provider_manual_setup },
        # set_models: fija a que modelos accede el team de la cuenta.
        'ai_provider.set_models' => { resource: 'ai_provider', action: 'edit',   handler: :ai_provider_set_models },
        # list_keys: virtual keys del team con su consumo (nunca la key en claro).
        'ai_provider.list_keys' => { resource: 'ai_provider', action: 'view',   handler: :ai_provider_list_keys },

        # --- Hermes POR CUENTA (crear/leer/editar el agente de cada cuenta) ---
        'hermes_instances.list' => { resource: 'hermes_instances', action: 'view',   handler: :hermes_list },
        'hermes_instances.get' => { resource: 'hermes_instances', action: 'view',   handler: :hermes_get },
        'hermes_instances.create' => { resource: 'hermes_instances', action: 'create', handler: :hermes_create },
        'hermes_instances.update' => { resource: 'hermes_instances', action: 'edit',   handler: :hermes_update },
        'hermes_instances.rotate_token' => { resource: 'hermes_instances', action: 'edit', handler: :hermes_rotate_token },
        'hermes_instances.verify' => { resource: 'hermes_instances', action: 'edit',   handler: :hermes_verify },

        # --- Automatizaciones de la cuenta ---
        'automations.list' => { resource: 'automations', action: 'view', handler: :automations_list },
        'automations.get' => { resource: 'automations', action: 'view', handler: :automations_get },
        'automations.set_active' => { resource: 'automations', action: 'edit', handler: :automations_set_active }
      }.freeze

      module_function

      def find(operation)
        OPERATIONS[operation.to_s]
      end

      def exists?(operation)
        OPERATIONS.key?(operation.to_s)
      end

      # Catálogo público (para discovery): operación → {resource, action}. Sin handlers.
      def catalog
        OPERATIONS.transform_values { |m| { resource: m[:resource], action: m[:action] } }
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
