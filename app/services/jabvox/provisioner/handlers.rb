# frozen_string_literal: true

# Handlers internos de la API Provisioner. Cada método recibe `params` (ya validados como
# whitelist de tipos en el ejecutor) y devuelve un Hash serializable. Reglas absolutas:
#   - NUNCA se toca la BD con SQL directo: solo modelos/servicios internos de Jabvox.
#   - NUNCA se devuelven credenciales/secretos: los "view" usan resúmenes saneados.
#   - NUNCA se borra nada.
# Los errores de negocio se lanzan como Jabvox::Provisioner::Handlers::OperationError.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Provisioner
    module Handlers # rubocop:disable Metrics/ModuleLength
      OperationError = Class.new(StandardError)

      module_function

      def error!(msg)
        raise OperationError, msg
      end

      def find_account!(id)
        Account.find_by(id: id) || error!("Cuenta #{id} no encontrada")
      end

      def find_user!(id)
        User.find_by(id: id) || error!("Usuario #{id} no encontrado")
      end

      # ---------------------------------------------------------------- Cuentas
      def list_accounts(params)
        scope = Account.order(:id)
        scope = scope.where('name ILIKE ?', "%#{like_escape(params['q'])}%") if params['q'].present?
        page = [params['page'].to_i, 1].max
        { accounts: scope.limit(50).offset((page - 1) * 50).map { |a| account_summary(a) }, page: page }
      end

      def get_account(params)
        { account: account_summary(find_account!(params['id']), full: true) }
      end

      def create_account(params)
        error!('name es requerido') if params['name'].blank?
        account = Account.create!(name: params['name'].to_s.strip)
        { account: account_summary(account, full: true) }
      end

      def update_account(params)
        account = find_account!(params['id'])
        attrs = {}
        attrs[:name] = params['name'].to_s.strip if params.key?('name') && params['name'].present?
        attrs[:jabvox_auto_renew] = to_bool(params['auto_renew']) if params.key?('auto_renew')
        account.update!(attrs) if attrs.any?
        { account: account_summary(account.reload, full: true) }
      end

      # ---------------------------------------------------------------- Usuarios
      def list_users(params)
        scope = User.order(:id)
        scope = scope.joins(:account_users).where(account_users: { account_id: params['account_id'] }) if params['account_id'].present?
        scope = scope.where('users.name ILIKE :q OR users.email ILIKE :q', q: "%#{like_escape(params['q'])}%") if params['q'].present?
        page = [params['page'].to_i, 1].max
        { users: scope.limit(50).offset((page - 1) * 50).map { |u| user_summary(u) }, page: page }
      end

      def get_user(params)
        { user: user_summary(find_user!(params['id']), full: true) }
      end

      def create_user(params) # rubocop:disable Metrics/AbcSize
        error!('name y email son requeridos') if params['name'].blank? || params['email'].blank?
        user = User.new(name: params['name'].to_s.strip, email: params['email'].to_s.strip.downcase)
        # Contraseña aleatoria fuerte: Hermes NUNCA fija ni recibe contraseñas.
        user.password = SecureRandom.urlsafe_base64(24)
        user.confirmed_at = Time.current
        user.save!
        if params['account_id'].present?
          account = find_account!(params['account_id'])
          role = %w[administrator agent].include?(params['role'].to_s) ? params['role'] : 'agent'
          AccountUser.create!(account: account, user: user, role: role)
        end
        { user: user_summary(user, full: true) }
      end

      def update_user(params) # rubocop:disable Metrics/AbcSize,Metrics/CyclomaticComplexity
        user = find_user!(params['id'])
        attrs = {}
        attrs[:name] = params['name'].to_s.strip if params.key?('name') && params['name'].present?
        user.update!(attrs) if attrs.any?
        if params['account_id'].present? && params['role'].present?
          role = params['role'].to_s
          error!('role inválido (usa administrator o agent)') unless %w[administrator agent].include?(role)
          au = AccountUser.find_by(account_id: params['account_id'], user_id: user.id)
          error!('el usuario no pertenece a esa cuenta') if au.nil?
          au.update!(role: role)
        end
        { user: user_summary(user.reload, full: true) }
      end

      # ---------------------------------------------------------------- Módulos de cuenta
      def get_account_modules(params)
        account = find_account!(params['id'])
        { account_id: account.id, modules: module_state(account) }
      end

      def set_account_modules(params) # rubocop:disable Naming/AccessorMethodName
        account = find_account!(params['id'])
        requested = params['modules']
        error!('modules debe ser un objeto {modulo: true/false}') unless requested.is_a?(Hash)

        updates = {}
        requested.each do |mod, on|
          col = module_column(mod)
          next if col.nil? # ignora módulos desconocidos (no revienta)

          updates[col] = to_bool(on)
        end
        account.update!(updates) if updates.any?
        { account_id: account.id, modules: module_state(account.reload) }
      end

      # ---------------------------------------------------------------- helpers de vista
      def account_summary(account, full: false)
        base = { id: account.id, name: account.name, created_at: account.created_at }
        return base unless full

        base.merge(
          plan_id: account.jabvox_plan_id,
          plan_expires_at: account.jabvox_plan_expires_at,
          auto_renew: account.jabvox_auto_renew,
          users_count: account.account_users.count,
          modules: module_state(account)
        )
      end

      def user_summary(user, full: false)
        base = { id: user.id, name: user.name, email: user.email }
        return base unless full

        base.merge(
          confirmed: user.confirmed?,
          accounts: user.account_users.map { |au| { account_id: au.account_id, role: au.role } }
        )
      end

      # Estado de módulos como { 'jabvox_dialer_enabled_jabvox' => true/false, ... }.
      def module_state(account)
        JabvoxModulesField::MODULES.each_with_object({}) do |(col, _label, _cat), acc|
          acc[col.to_s] = account.respond_to?(col) ? account.public_send(col) == true : nil
        end.compact
      end

      def module_column(mod)
        cols = JabvoxModulesField::MODULES.map { |(col, _l, _c)| col.to_s }
        name = mod.to_s
        name = "jabvox_#{name}_enabled_jabvox" unless name.start_with?('jabvox_')
        cols.include?(name) ? name.to_sym : nil
      end

      def to_bool(val)
        [true, 'true', 1, '1', 'on', 'yes'].include?(val)
      end

      # Escapa los metacaracteres LIKE (%, _) del input y lo acota, para evitar patrones
      # costosos (DoS) y comodines inyectados. El bind param ya evita inyección SQL.
      def like_escape(str)
        ActiveRecord::Base.sanitize_sql_like(str.to_s[0, 100])
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
