# frozen_string_literal: true

# Segunda parte de los handlers de la API Provisioner: planes, solo-lectura sensible
# (pasarelas/transacciones/saldo/data sources), límites, IP whitelist, softphone, tokens de
# los Hermes de la cuenta y leads. Mismas reglas: sin SQL directo, sin credenciales, sin borrar.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Provisioner
    module HandlersAdmin # rubocop:disable Metrics/ModuleLength
      module_function

      def h = Jabvox::Provisioner::Handlers

      # ---------------------------------------------------------------- Planes
      def list_plans(_params)
        { plans: JabvoxPlan.order(:sort_order, :id).map { |p| plan_summary(p) } }
      end

      def get_plan(params)
        { plan: plan_summary(find_plan!(params['id']), full: true) }
      end

      def create_plan(params) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        h.error!('name y slug son requeridos') if params['name'].blank? || params['slug'].blank?
        plan = JabvoxPlan.create!(
          name: params['name'].to_s.strip, slug: params['slug'].to_s.strip,
          price_cents: params['price_cents'].to_i, currency: (params['currency'].presence || 'COP'),
          duration_days: (params['duration_days'].presence || 30).to_i,
          modules: Array(params['modules']).map(&:to_s), chatwoot_features: Array(params['features']).map(&:to_s),
          limits: params['limits'].is_a?(Hash) ? params['limits'] : {},
          status: plan_status(params['status'])
        )
        { plan: plan_summary(plan, full: true) }
      end

      def update_plan(params) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity,Metrics/PerceivedComplexity
        plan = find_plan!(params['id'])
        attrs = {}
        attrs[:name] = params['name'].to_s.strip if params.key?('name') && params['name'].present?
        attrs[:price_cents] = params['price_cents'].to_i if params.key?('price_cents')
        attrs[:currency] = params['currency'] if params.key?('currency') && params['currency'].present?
        attrs[:duration_days] = params['duration_days'].to_i if params.key?('duration_days')
        attrs[:modules] = Array(params['modules']).map(&:to_s) if params.key?('modules')
        attrs[:chatwoot_features] = Array(params['features']).map(&:to_s) if params.key?('features')
        attrs[:limits] = params['limits'] if params.key?('limits') && params['limits'].is_a?(Hash)
        plan.update!(attrs) if attrs.any?
        { plan: plan_summary(plan.reload, full: true) }
      end

      def set_plan_status(params) # rubocop:disable Naming/AccessorMethodName
        plan = find_plan!(params['id'])
        plan.update!(status: plan_status(params['status']))
        { plan: plan_summary(plan, full: true) }
      end

      def assign_plan_to_account(params)
        account = h.find_account!(params['account_id'])
        plan = find_plan!(params['plan_id'])
        attrs = { jabvox_plan_id: plan.id }
        if params['expires_at'].present?
          # Parseo estricto: una fecha malformada da error claro (422) en vez de un 500 o un nil silencioso.
          expires = begin
            Time.zone.parse(params['expires_at'].to_s)
          rescue ArgumentError, TypeError
            nil
          end
          h.error!('expires_at inválido (usa ISO 8601, ej. 2026-12-31T23:59:59Z)') if expires.nil?
          attrs[:jabvox_plan_expires_at] = expires
        end
        account.update!(attrs)
        { account_id: account.id, plan_id: plan.id, plan_expires_at: account.reload.jabvox_plan_expires_at }
      end

      # ---------------------------------------------------------------- Solo lectura sensible
      def list_payment_gateways(_params)
        {
          # NUNCA api_key/secret_key: solo metadatos.
          gateways: JabvoxPaymentGatewayConfig.order(:id).map do |g|
            { id: g.id, provider: g.provider, active: g.active, sandbox: g.sandbox,
              checkout_base_url: g.checkout_base_url }
          end
        }
      end

      def list_transactions(params)
        scope = JabvoxProvisioningTransaction.order(created_at: :desc)
        scope = scope.where(account_id: params['account_id']) if params['account_id'].present?
        scope = scope.where(status: params['status']) if params['status'].present?
        page = [params['page'].to_i, 1].max
        { transactions: scope.limit(50).offset((page - 1) * 50).map { |t| transaction_summary(t) }, page: page }
      end

      def get_transaction(params)
        tx = JabvoxProvisioningTransaction.find_by(id: params['id']) || h.error!('Transacción no encontrada')
        { transaction: transaction_summary(tx, full: true) }
      end

      def get_saldo(params)
        account = h.find_account!(params['account_id'])
        cfg = account.jabvox_saldo_config
        return { account_id: account.id, saldo: nil } if cfg.nil?

        # NUNCA api_key/api_secret: solo el balance cacheado y metadatos.
        { account_id: account.id, saldo: {
          active: cfg.is_active_jabvox, cached_balance: cfg.cached_balance_jabvox,
          balance_updated_at: cfg.balance_updated_at_jabvox, base_url: cfg.base_url_jabvox
        } }
      end

      def list_data_sources(params)
        account = h.find_account!(params['account_id'])
        # provisioner_summary NO incluye password/ssl_ca (solo lectura de metadatos).
        { account_id: account.id, data_sources: account.jabvox_analytics_data_sources.order(:id).map(&:provisioner_summary) }
      end

      # ---------------------------------------------------------------- Límites
      def get_limits(params)
        account = h.find_account!(params['id'])
        { account_id: account.id, limits: (account.limits || {}) }
      end

      def set_limits(params) # rubocop:disable Naming/AccessorMethodName
        account = h.find_account!(params['id'])
        h.error!('limits debe ser un objeto') unless params['limits'].is_a?(Hash)
        # merge no destructivo; Account valida las claves permitidas (validate_limit_keys).
        account.update!(limits: (account.limits || {}).merge(params['limits']))
        { account_id: account.id, limits: account.reload.limits }
      end

      # ---------------------------------------------------------------- IP whitelist
      def list_ip_whitelists(params)
        account = h.find_account!(params['account_id'])
        { account_id: account.id, ips: account.jabvox_ip_whitelists.ordered.map do |w|
          { id: w.id, ip: w.ip, comment: w.comment, is_active: w.is_active }
        end }
      end

      def create_ip_whitelist(params)
        account = h.find_account!(params['account_id'])
        h.error!('ip es requerida') if params['ip'].blank?
        ip = params['ip'].to_s.strip
        # Valida que sea una IP/CIDR real antes de escribir en la allowlist.
        begin
          IPAddr.new(ip)
        rescue IPAddr::Error
          h.error!('ip inválida')
        end
        w = account.jabvox_ip_whitelists.create!(ip: ip, comment: params['comment'].to_s.presence, is_active: true)
        { id: w.id, ip: w.ip, is_active: w.is_active }
      end

      def set_ip_whitelist_active(params) # rubocop:disable Naming/AccessorMethodName
        account = h.find_account!(params['account_id'])
        w = account.jabvox_ip_whitelists.find_by(id: params['id']) || h.error!('IP no encontrada')
        w.update!(is_active: h.to_bool(params['active']))
        { id: w.id, ip: w.ip, is_active: w.is_active }
      end

      # ---------------------------------------------------------------- Softphone
      def get_softphone(params)
        account = h.find_account!(params['account_id'])
        {
          account_id: account.id,
          softphone_enabled: account.respond_to?(:jabvox_softphone_enabled_jabvox) ? account.jabvox_softphone_enabled_jabvox == true : nil,
          extensions: account.jabvox_user_extensions.map { |e| { id: e.id, user_id: e.user_id, extension: e.extension_jabvox } }
        }
      end

      def create_extension(params)
        account = h.find_account!(params['account_id'])
        user = h.find_user!(params['user_id'])
        h.error!('extension es requerida') if params['extension'].blank?
        ext = account.jabvox_user_extensions.create!(user: user, extension_jabvox: params['extension'].to_s.strip)
        { id: ext.id, account_id: account.id, user_id: user.id, extension: ext.extension_jabvox }
      end

      def set_softphone_enabled(params) # rubocop:disable Naming/AccessorMethodName
        account = h.find_account!(params['account_id'])
        col = :jabvox_softphone_enabled_jabvox
        h.error!('la cuenta no soporta softphone') unless account.respond_to?(col)
        account.update!(col => h.to_bool(params['enabled']))
        # Si se indica user_id, habilita/deshabilita la extensión WebRTC de ese usuario.
        # OJO: se busca SIN el scope active (JabvoxSoftphoneExtension.for filtra webrtc_enabled:
        # true), porque al REACTIVAR una extensión deshabilitada .for devolvería nil y no
        # aplicaría el cambio. find_by por (cuenta, usuario) la encuentra en cualquier estado.
        if params['user_id'].present?
          sp = JabvoxSoftphoneExtension.find_by(account_id: account.id, user_id: params['user_id'])
          sp&.update!(webrtc_enabled: h.to_bool(params['enabled']))
        end
        { account_id: account.id, softphone_enabled: account.reload.public_send(col) == true }
      end

      # ---------------------------------------------------------------- Tokens de Hermes de la cuenta
      def list_hermes_tokens(params)
        account = h.find_account!(params['account_id'])
        # NUNCA se devuelve el action_token en claro (es una credencial cifrada): solo
        # metadatos + si existe o no. Ligar/rotar el token se hace desde el Super Admin.
        { account_id: account.id, hermes: account.jabvox_hermes_connections.map do |c|
          { id: c.id, name: c.name_jabvox, hermes_agent: c.hermes_agent_name_jabvox,
            base_url: c.base_url_jabvox, has_action_token: c.action_token_jabvox.present? }
        end }
      end

      # ---------------------------------------------------------------- Leads
      def list_leads(params)
        account = h.find_account!(params['account_id'])
        scope = account.jabvox_leads.order(created_at: :desc)
        page = [params['page'].to_i, 1].max
        { account_id: account.id, leads: scope.limit(50).offset((page - 1) * 50).map do |l|
          { id: l.id, name: l.try(:name), phone: l.try(:phone), email: l.try(:email) }
        end, page: page }
      end

      def list_lead_import_sources(params)
        account = h.find_account!(params['account_id'])
        rel = account.try(:jabvox_lead_import_sources)
        return { account_id: account.id, sources: [] } if rel.nil?

        # Sin credenciales de la BD externa: solo metadatos.
        { account_id: account.id, sources: rel.map do |s|
          { id: s.id, name: s.try(:name_jabvox) || s.try(:name), status: s.try(:status_jabvox) || s.try(:status) }
        end }
      end

      def trigger_lead_import(params)
        account = h.find_account!(params['account_id'])
        rel = account.try(:jabvox_lead_import_sources)
        src = rel&.find_by(id: params['source_id']) || h.error!('Fuente de importación no encontrada')
        # Encola el sync existente (nunca ejecuta SQL directo).
        Jabvox::LeadImport::SyncJob.perform_later(src.id) if defined?(Jabvox::LeadImport::SyncJob)
        { account_id: account.id, source_id: src.id, queued: true }
      end

      def list_lead_export_targets(params)
        account = h.find_account!(params['account_id'])
        rel = account.try(:jabvox_export_targets)
        return { account_id: account.id, targets: [] } if rel.nil?

        { account_id: account.id, targets: rel.map { |t| { id: t.id, status: t.try(:status_jabvox) || t.try(:status) } } }
      end

      # ---------------------------------------------------------------- helpers
      def find_plan!(id)
        JabvoxPlan.find_by(id: id) || h.error!("Plan #{id} no encontrado")
      end

      def plan_status(val)
        %w[draft active in_development].include?(val.to_s) ? val.to_s : 'draft'
      end

      def plan_summary(plan, full: false)
        base = { id: plan.id, name: plan.name, slug: plan.slug, status: plan.status,
                 price_cents: plan.price_cents, currency: plan.currency }
        return base unless full

        base.merge(duration_days: plan.duration_days, modules: Array(plan.modules),
                   features: Array(plan.chatwoot_features), limits: (plan.limits || {}))
      end

      def transaction_summary(tx, full: false) # rubocop:disable Naming/MethodParameterName
        base = { id: tx.id, gateway: tx.gateway, status: tx.status, amount_cents: tx.amount_cents,
                 currency: tx.currency, account_id: tx.account_id, created_at: tx.created_at }
        return base unless full

        base.merge(status_reason: tx.status_reason, buyer_email: tx.buyer_email,
                   jabvox_plan_id: tx.jabvox_plan_id, gateway_reference: tx.gateway_reference)
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
