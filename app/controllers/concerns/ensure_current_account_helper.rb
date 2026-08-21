module EnsureCurrentAccountHelper
  private

  def current_account
    @current_account ||= ensure_current_account
    Current.account = @current_account
  end

  def ensure_current_account
    account = Account.find(params[:account_id])
    # Cuentas no activas (payment_pending/suspended) quedan bloqueadas EN TODA la app,
    # salvo los endpoints de pago: si no los dejáramos pasar, el usuario no podría ni
    # consultar su estado ni iniciar el checkout para desbloquearse. Cada controlador de
    # billing declara allow_inactive_account? => true.
    render_unauthorized('Account is suspended') and return unless account.active? || allow_inactive_account?

    if current_user
      account_accessible_for_user?(account)
    elsif @resource.is_a?(AgentBot)
      account_accessible_for_bot?(account)
    else
      render_unauthorized(I18n.t('errors.account.not_authorized'))
    end
    account
  end

  # Por defecto NINGÚN controlador permite operar con la cuenta inactiva. Los
  # controladores de billing (status/checkout/renewals) lo sobrescriben a true para que
  # el usuario pueda pagar y desbloquear su cuenta.
  def allow_inactive_account?
    false
  end

  def account_accessible_for_user?(account)
    @current_account_user = account.account_users.find_by(user_id: current_user.id)
    Current.account_user = @current_account_user
    render_unauthorized(I18n.t('errors.account.not_authorized')) unless @current_account_user
  end

  def account_accessible_for_bot?(account)
    return if @resource.account_id == account.id
    return if @resource.agent_bot_inboxes.find_by(account_id: account.id)

    render_unauthorized('Bot is not authorized to access this account')
  end
end
