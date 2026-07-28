# frozen_string_literal: true

# Revoca los usuarios de servicio que creaba el eliminado Automations::ServiceUserService.
# NO EJECUTADO: se corre a mano en producción tras desplegar el selector de usuario.
module JabvoxAutomationsServiceUserRevocation
  SERVICE_FLAG_KEY = 'jabvox_service_user'
  SERVICE_FLAG_VALUE = 'automations'
  SERVICE_EMAIL_LIKE = 'automations-service+%@jabvox.invalid'

  # Se buscan por marcador Y por email: son redundantes a propósito, para no
  # dejar fuera una credencial de administrador si a uno le editaron los atributos.
  def self.find_service_users(account_id)
    scope = User.where("custom_attributes->>'#{SERVICE_FLAG_KEY}' = ?", SERVICE_FLAG_VALUE)
                .or(User.where('email LIKE ?', SERVICE_EMAIL_LIKE))
    scope = scope.where(id: AccountUser.where(account_id: account_id).select(:user_id)) if account_id
    scope.order(:id)
  end

  def self.process_user(user, apply:)
    memberships = user.account_users.to_a
    token = user.access_token
    report_user(user, token, memberships)

    unless apply
      puts "  → [dry-run] se destruiría el access token y las membresías; el User se conservaría.\n"
      return
    end

    revoke!(user, token, memberships)
    puts ''
  end

  def self.report_user(user, token, memberships)
    puts "User ##{user.id} <#{user.email}> — #{user.name}"
    puts "  access_token: #{token ? "presente (creado #{token.created_at})" : 'ninguno'}"
    if memberships.empty?
      puts '  membresías:   ninguna (ya estaba desactivado)'
    else
      memberships.each { |m| puts "  membresía:    cuenta #{m.account_id}, rol #{m.role}" }
    end
  end

  # Revoca el ACCESO (token + membresías) pero NO borra el User: `Message#sender` y
  # `Conversation#assignee` apuntan a él y borrarlo reescribiría el histórico.
  def self.revoke!(user, token, memberships)
    ActiveRecord::Base.transaction do
      token&.destroy!
      memberships.each(&:destroy!)
      user.update!(
        custom_attributes: user.custom_attributes.to_h.merge(
          'jabvox_service_revoked_at' => Time.current.iso8601,
          'jabvox_service_revoked_reason' => 'ServiceUserService eliminado: sustituido por selector de usuario'
        )
      )
    end
    puts '  → REVOCADO: access token destruido, membresías retiradas, User conservado.'
  rescue StandardError => e
    # No se aborta el bucle: si uno falla, los demás deben revocarse igualmente.
    puts "  → ERROR al revocar User ##{user.id}: #{e.class}: #{e.message}"
  end
end

namespace :jabvox do
  namespace :automations do
    desc 'Revoca el acceso (access token + membresías) de los usuarios de servicio de Automations, ' \
         'conservando el registro de User para el histórico de auditoría. ' \
         'Simula por defecto; escribe solo con APPLY=yes. Acota a una cuenta con ACCOUNT_ID=N. ' \
         'Uso: RAILS_ENV=production APPLY=yes bundle exec rake jabvox:automations:revoke_service_users'
    task revoke_service_users: :environment do
      # Dry-run por defecto: revocar credenciales de administrador en producción no
      # debe poder dispararse por un error de historial de shell.
      apply = ENV.fetch('APPLY', nil) == 'yes'
      helper = JabvoxAutomationsServiceUserRevocation
      users = helper.find_service_users(ENV.fetch('ACCOUNT_ID', nil).presence)

      if users.empty?
        puts 'No se ha encontrado ningún usuario de servicio de Automations. Nada que hacer.'
        next
      end

      puts(apply ? '=== EJECUCIÓN REAL (APPLY=yes) ===' : '=== SIMULACIÓN (dry-run). Usa APPLY=yes para aplicar. ===')
      puts "Usuarios de servicio encontrados: #{users.size}\n\n"

      users.each { |user| helper.process_user(user, apply: apply) }

      if apply
        puts "\nHecho. Las cuentas afectadas quedan sin credencial saliente: elige un usuario en"
        puts '/super_admin/accounts/:id/account_automations y pulsa "Guardar y aprovisionar".'
      else
        puts "\nNo se ha modificado nada. Repite con APPLY=yes para aplicar."
      end
    end
  end
end
