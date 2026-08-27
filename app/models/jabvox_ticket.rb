# Ticket (solicitud/incidente/requerimiento) del helpdesk. Pertenece a una cuenta,
# tiene un solicitante (requester) y opcionalmente un responsable (assignee), una
# categoría, y puede nacer desde una conversación. El ciclo de vida vive en el
# concern TicketLifecycle; los permisos en JabvoxTicketPolicy.
# rubocop:disable Layout/LineLength
# == Schema Information
#
# Table name: jabvox_tickets
#
#  id                          :bigint           not null, primary key
#  category_type_jabvox        :integer          default("incident"), not null
#  closed_at_jabvox            :datetime
#  comments_count_jabvox       :integer          default(0), not null
#  custom_attributes_jabvox    :jsonb            not null
#  deleted_at_jabvox           :datetime
#  description_jabvox          :text
#  display_id_jabvox           :integer          not null
#  due_at_jabvox               :datetime
#  first_response_at_jabvox    :datetime
#  lock_version                :integer          default(0), not null
#  priority_jabvox             :integer          default("medium"), not null
#  reopened_count_jabvox       :integer          default(0), not null
#  resolution_jabvox           :text
#  resolution_type_jabvox      :integer
#  resolved_at_jabvox          :datetime
#  satisfaction_comment_jabvox :text
#  satisfaction_rating_jabvox  :integer
#  search_vector_jabvox        :tsvector
#  sla_escalated_at_jabvox     :datetime
#  sla_warned_at_jabvox        :datetime
#  status_jabvox               :integer          default("new_ticket"), not null
#  title_jabvox                :string           not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :integer          not null
#  assignee_id                 :integer
#  contact_id                  :integer
#  conversation_id             :integer
#  requester_id                :integer          not null
#  ticket_category_id          :integer
#
# Indexes
#
#  idx_tickets_account_assignee   (account_id,assignee_id)
#  idx_tickets_account_ctype      (account_id,category_type_jabvox)
#  idx_tickets_account_deleted    (account_id,deleted_at_jabvox)
#  idx_tickets_account_display    (account_id,display_id_jabvox) UNIQUE
#  idx_tickets_account_requester  (account_id,requester_id)
#  idx_tickets_account_status     (account_id,status_jabvox)
#  idx_tickets_open_due           (account_id,due_at_jabvox) WHERE ((status_jabvox <> ALL (ARRAY[4, 5])) AND (deleted_at_jabvox IS NULL))
#  idx_tickets_search_vector      (search_vector_jabvox) USING gin
#  idx_tickets_sla_pending        (due_at_jabvox) WHERE ((status_jabvox <> ALL (ARRAY[4, 5])) AND (sla_escalated_at_jabvox IS NULL) AND (deleted_at_jabvox IS NULL))
#
# rubocop:enable Layout/LineLength
class JabvoxTicket < ApplicationRecord
  include Jabvox::TicketLifecycle
  include Jabvox::TicketImageAttachable
  include PgSearch::Model

  self.table_name = 'jabvox_tickets'

  # Búsqueda full-text sobre la columna tsvector generada (índice GIN), en vez de
  # ILIKE '%...%'. La columna ya está normalizada con unaccent en la BD; aquí se
  # normaliza el término buscado con el mismo wrapper para que ignore acentos
  # (produccion == producción). Reemplaza el filtro de texto de la lista.
  pg_search_scope(
    :text_search,
    against: :title_jabvox,
    using: {
      tsearch: { tsvector_column: 'search_vector_jabvox', prefix: true, dictionary: 'simple' }
    }
  )

  # Envuelve text_search normalizando el término (acentos → sin acentos) con el mismo
  # wrapper de la columna generada. Úsese este en vez de text_search directo.
  def self.accent_insensitive_search(term)
    normalized = connection.select_value(
      sanitize_sql_array(['SELECT jabvox_immutable_unaccent(?)', term.to_s])
    )
    text_search(normalized)
  end

  belongs_to :account
  belongs_to :category, class_name: 'JabvoxTicketCategory', foreign_key: :ticket_category_id,
                        inverse_of: :tickets, optional: true
  belongs_to :requester, class_name: 'User'
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
  has_many :comments, class_name: 'JabvoxTicketComment', foreign_key: :ticket_id,
                      inverse_of: :ticket, dependent: :destroy, counter_cache: :comments_count_jabvox
  has_many :activities, class_name: 'JabvoxTicketActivity', foreign_key: :ticket_id,
                        inverse_of: :ticket, dependent: :destroy

  enum category_type_jabvox: { incident: 0, requirement: 1, request: 2 }, _prefix: :type
  enum priority_jabvox: { low: 0, medium: 1, high: 2, urgent: 3 }, _prefix: :priority
  enum status_jabvox: { new_ticket: 0, assigned: 1, in_progress: 2, on_hold: 3,
                        resolved: 4, closed: 5, reopened: 6 }, _prefix: :status
  enum resolution_type_jabvox: { solved: 0, duplicate: 1, rejected: 2 }, _prefix: :resolution

  OPEN_STATUSES = %w[new_ticket assigned in_progress on_hold reopened].freeze

  validates :title_jabvox, presence: true
  validates :satisfaction_rating_jabvox, inclusion: { in: 1..5 }, allow_nil: true
  validate :category_belongs_to_manager_account

  before_validation :assign_display_id, on: :create
  before_validation :denormalize_category_type
  before_create :set_due_at
  after_commit :invalidate_metrics_cache

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :for_requester, ->(user_id) { where(requester_id: user_id) }
  scope :for_assignee, ->(user_id) { where(assignee_id: user_id) }
  scope :kept, -> { where(deleted_at_jabvox: nil) }
  scope :archived, -> { where.not(deleted_at_jabvox: nil) }
  scope :open_tickets, -> { kept.where(status_jabvox: OPEN_STATUSES) }
  scope :closed_tickets, -> { kept.where(status_jabvox: %w[resolved closed]) }
  scope :overdue, -> { open_tickets.where('due_at_jabvox IS NOT NULL AND due_at_jabvox < ?', Time.current) }
  # Abiertos vencidos aún sin escalar: alineado con idx_tickets_sla_pending.
  scope :sla_pending_escalation, lambda {
    open_tickets.where('due_at_jabvox IS NOT NULL AND due_at_jabvox < ?', Time.current)
                .where(sla_escalated_at_jabvox: nil)
  }

  def open?
    OPEN_STATUSES.include?(status_jabvox)
  end

  def overdue?
    open? && due_at_jabvox.present? && due_at_jabvox < Time.current
  end

  def archived?
    deleted_at_jabvox.present?
  end

  # Minutos que faltan para el vencimiento (negativo si ya venció); nil sin due_at.
  def minutes_to_due
    return nil if due_at_jabvox.nil?

    ((due_at_jabvox - Time.current) / 60).round
  end

  # Semáforo de SLA para el frontend (contador visual):
  #   none   → sin due_at o ya cerrado/resuelto
  #   red    → vencido
  #   amber  → queda < 25% de margen aprox. (menos de 60 min o < 10% del SLA)
  #   green  → dentro de plazo cómodo
  def sla_status
    return 'none' if due_at_jabvox.nil? || !open?

    remaining = minutes_to_due
    return 'red' if remaining.negative?
    return 'amber' if remaining <= amber_threshold_minutes

    'green'
  end

  # Soft delete: archiva sin perder historial ni romper métricas.
  def archive!(actor: nil)
    return if archived?

    update!(deleted_at_jabvox: Time.current)
    log_activity!('archived', actor: actor)
  end

  # Datos para el push (FCM/móvil) de una notificación cuyo primary_actor es este
  # ticket. Notification#fcm_push_data llama a este método; sin él rompería el push.
  def push_event_data
    {
      id: id,
      display_id: display_id_jabvox,
      title: title_jabvox,
      status: status_jabvox
    }
  end

  private

  # Umbral de "ámbar": el máximo entre 60 min y el 10% del SLA de la categoría.
  def amber_threshold_minutes
    sla = category&.sla_resolution_minutes_jabvox.to_i
    [(sla * 0.1).round, 60].max
  end

  # display_id secuencial por cuenta (patrón lead_number: sin trigger, sobre BD).
  def assign_display_id
    return if display_id_jabvox.present?

    last = self.class.for_account(account_id).maximum(:display_id_jabvox) || 0
    self.display_id_jabvox = last + 1
  end

  def denormalize_category_type
    self.category_type_jabvox = category.category_type_jabvox if category.present?
  end

  # Seguridad: los temas están centralizados en la cuenta gestora. Un ticket solo
  # puede referenciar una categoría que pertenezca a esa cuenta gestora (impide
  # inyectar una categoría arbitraria de otra cuenta vía la API).
  def category_belongs_to_manager_account
    return if category.nil?

    manager_account = JabvoxTicketHelpdeskConfig.manager_account
    return if manager_account && category.account_id == manager_account.id

    errors.add(:ticket_category_id, 'no pertenece a la cuenta gestora del helpdesk')
  end

  # SLA de resolución de la categoría → due_at, calculado sobre el horario laboral
  # de la cuenta gestora (no en tiempo corrido).
  def set_due_at
    return if due_at_jabvox.present? || category.nil?

    from = created_at.presence || Time.current
    self.due_at_jabvox = Jabvox::Tickets::DueAtCalculator.new(
      category.sla_resolution_minutes_jabvox, from: from
    ).call
  end

  # Bumpea el epoch de caché de métricas de la cuenta al cambiar cualquier ticket.
  def invalidate_metrics_cache
    Jabvox::Tickets::MetricsService.touch_cache!(account_id)
  end
end
