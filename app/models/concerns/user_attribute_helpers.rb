module UserAttributeHelpers
  extend ActiveSupport::Concern

  def available_name
    self[:display_name].presence || name
  end

  def availability_status
    current_account_user&.availability_status
  end

  def auto_offline
    current_account_user&.auto_offline
  end

  def inviter
    current_account_user&.inviter
  end

  def active_account_user
    account_users.order(Arel.sql('active_at DESC NULLS LAST'))&.first
  end

  def current_account_user
    # We want to avoid subsequent queries in case where the association is preloaded.
    # using where here will trigger n+1 queries.
    account_users.find { |ac_usr| ac_usr.account_id == Current.account.id } if Current.account
  end

  def account
    current_account_user&.account
  end

  def administrator?
    current_account_user&.administrator?
  end

  def agent?
    current_account_user&.agent?
  end

  def role
    current_account_user&.role
  end

  # Used internally for Jabvox in Jabvox (widget de soporte global).
  # Firma un identifier con la clave HMAC global de la bandeja de soporte.
  # Si no se pasa identifier, firma el email (compatibilidad hacia atrás).
  def hmac_identifier(identifier = nil)
    hmac_key = GlobalConfig.get('JABVOX_INBOX_HMAC_KEY')['JABVOX_INBOX_HMAC_KEY']
    return '' if hmac_key.blank?

    OpenSSL::HMAC.hexdigest('sha256', hmac_key, identifier.presence || email)
  end

  # Hash HMAC por cada cuenta del usuario, para el widget de soporte. El
  # identifier es "email:account_id" de modo que el MISMO usuario en cuentas
  # distintas sea un CONTACTO distinto en la bandeja de soporte (nombre e
  # historial por cuenta). Devuelve { account_id => hmac } para que el
  # frontend elija el de la cuenta activa sin recargar.
  def support_hmac_identifiers
    hmac_key = GlobalConfig.get('JABVOX_INBOX_HMAC_KEY')['JABVOX_INBOX_HMAC_KEY']
    return {} if hmac_key.blank?

    account_ids.index_with do |account_id|
      OpenSSL::HMAC.hexdigest('sha256', hmac_key, "#{email}:#{account_id}")
    end
  end
end
