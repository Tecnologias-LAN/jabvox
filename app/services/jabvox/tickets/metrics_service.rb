# Calcula las métricas del dashboard de tickets sobre un scope ya filtrado por
# permisos (staff → toda la cuenta gestora; requester → solo lo suyo). Devuelve
# totales, distribuciones, tiempo medio de resolución, cumplimiento de SLA, creados
# en 30 días y satisfacción promedio.
#
# El endpoint recalcula ~10 GROUP BY; para no rehacerlos en cada carga se cachea el
# resultado en Rails.cache (Redis) con una clave que incluye un "epoch" por cuenta.
# Cualquier cambio en un ticket bumpea el epoch (touch_cache!), invalidando al vuelo.
class Jabvox::Tickets::MetricsService
  CACHE_TTL = 5.minutes

  def initialize(scope)
    @scope = scope
  end

  # Devuelve las métricas cacheadas para (cuenta, discriminante de permiso). El
  # discriminante distingue el scope de un staff (toda la cuenta) del de un
  # requester (solo lo suyo), para no servir datos cruzados desde caché.
  def self.cached(scope, account_id:, discriminator:)
    key = cache_key(account_id, discriminator)
    Rails.cache.fetch(key, expires_in: CACHE_TTL) { new(scope).call }
  end

  # Invalida la caché de métricas de una cuenta bumpeando su epoch.
  def self.touch_cache!(account_id)
    Rails.cache.write(epoch_key(account_id), current_epoch_token)
  end

  def self.cache_key(account_id, discriminator)
    epoch = Rails.cache.fetch(epoch_key(account_id)) { current_epoch_token }
    "jabvox_tickets/metrics/#{account_id}/#{discriminator}/#{epoch}"
  end

  def self.epoch_key(account_id)
    "jabvox_tickets/metrics_epoch/#{account_id}"
  end

  # Token monótono para invalidar; usa el reloj pero cae en un contador si no está.
  def self.current_epoch_token
    (Time.current.to_f * 1000).to_i
  end

  def call
    {
      totals: totals,
      by_status: distribution(:status_jabvox),
      by_type: distribution(:category_type_jabvox),
      by_priority: distribution(:priority_jabvox),
      by_category: by_category,
      by_agent: by_agent,
      avg_resolution_minutes: avg_resolution_minutes,
      sla_compliance_pct: sla_compliance_pct,
      created_last_30_days: created_last_30_days,
      avg_satisfaction: avg_satisfaction
    }
  end

  private

  def totals
    {
      total: @scope.count,
      open: @scope.open_tickets.count,
      resolved: @scope.where(status_jabvox: :resolved).count,
      closed: @scope.where(status_jabvox: :closed).count,
      overdue: @scope.overdue.count
    }
  end

  def distribution(column)
    @scope.group(column).count
  end

  def by_category
    @scope.joins(:category).group('jabvox_ticket_categories.name_jabvox').count
  end

  def by_agent
    @scope.where.not(assignee_id: nil).joins(:assignee).group('users.name').count
  end

  # Minutos promedio entre creación y resolución de los tickets resueltos.
  def avg_resolution_minutes
    resolved = @scope.where.not(resolved_at_jabvox: nil)
    return 0 if resolved.count.zero?

    seconds = resolved.pluck(:created_at, :resolved_at_jabvox).sum { |c, r| (r - c).to_i }
    (seconds / resolved.count / 60.0).round(1)
  end

  # % de tickets resueltos dentro de su SLA (resolved_at <= due_at).
  def sla_compliance_pct
    with_due = @scope.where.not(resolved_at_jabvox: nil).where.not(due_at_jabvox: nil)
    total = with_due.count
    return 100.0 if total.zero?

    on_time = with_due.where('resolved_at_jabvox <= due_at_jabvox').count
    ((on_time.to_f / total) * 100).round(1)
  end

  def created_last_30_days
    @scope.where('created_at >= ?', 30.days.ago)
          .group('DATE(created_at)').count
          .transform_keys(&:to_s)
  end

  def avg_satisfaction
    rated = @scope.where.not(satisfaction_rating_jabvox: nil)
    return nil if rated.count.zero?

    (rated.average(:satisfaction_rating_jabvox) || 0).to_f.round(2)
  end
end
