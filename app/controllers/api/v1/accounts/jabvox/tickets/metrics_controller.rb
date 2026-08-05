# Métricas del dashboard de tickets. El scope se filtra por permisos: staff ve toda
# la operación; un requester ve solo lo suyo (mismo Scope que el listado). El
# resultado se cachea por (cuenta, discriminante de permiso) y se invalida al cambiar
# cualquier ticket de la cuenta.
class Api::V1::Accounts::Jabvox::Tickets::MetricsController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  def show
    scope = policy_scope(JabvoxTicket)
    metrics = Jabvox::Tickets::MetricsService.cached(
      scope, account_id: Current.account.id, discriminator: cache_discriminator
    )
    render json: metrics
  end

  private

  # Distingue el scope amplio (staff ve todo) del acotado (resolver/requester ven un
  # subconjunto propio), para no servir métricas cruzadas desde caché.
  def cache_discriminator
    return 'staff' if ticket_permission.staff?

    "user_#{Current.user.id}"
  end
end
