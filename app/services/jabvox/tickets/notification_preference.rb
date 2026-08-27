# Preferencia de notificaciones de tickets por usuario. Se guarda en user.ui_settings
# (jsonb) bajo la clave 'jabvox_tickets_notifications' para no crear otra tabla.
# Por defecto todo está activo; el usuario puede silenciar in-app y/o email.
class Jabvox::Tickets::NotificationPreference
  KEY = 'jabvox_tickets_notifications'.freeze

  def initialize(user)
    @user = user
  end

  def in_app?
    prefs.fetch('in_app', true)
  end

  def email?
    prefs.fetch('email', true)
  end

  # Actualiza las preferencias (merge parcial) y persiste.
  def update!(in_app: nil, email: nil)
    updated = prefs.dup
    updated['in_app'] = in_app unless in_app.nil?
    updated['email'] = email unless email.nil?
    settings = (@user.ui_settings || {}).merge(KEY => updated)
    @user.update!(ui_settings: settings)
    self
  end

  def to_h
    { in_app: in_app?, email: email? }
  end

  private

  def prefs
    (@user.ui_settings || {})[KEY] || {}
  end
end
