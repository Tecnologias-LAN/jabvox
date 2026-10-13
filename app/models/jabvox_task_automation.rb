# A recurring automation attached to a single task: every N days/weeks/months it sends an
# email / sms / inbox message to some combination of the lead, the task assignees, the lead's
# captured contacts, and/or a manual address. A daily scheduled job picks up rows whose
# next_run_at has passed and dispatches them via Jabvox::TaskAutomationDispatchService.
# == Schema Information
#
# Table name: jabvox_task_automations
#
#  id                          :bigint           not null, primary key
#  active_jabvox               :boolean          default(TRUE), not null
#  assignee_contact_map_jabvox :jsonb            not null
#  body_jabvox                 :text
#  channel_jabvox              :string           not null
#  end_at_jabvox               :datetime
#  interval_count_jabvox       :integer          default(1), not null
#  interval_unit_jabvox        :string           default("day"), not null
#  last_run_at_jabvox          :datetime
#  manual_email_jabvox         :string           default(""), not null
#  manual_phone_jabvox         :string           default(""), not null
#  max_runs_jabvox             :integer
#  name_jabvox                 :string           default(""), not null
#  next_run_at_jabvox          :datetime
#  recipients_jabvox           :string           default("lead"), not null
#  runs_count_jabvox           :integer          default(0), not null
#  schedule_mode_jabvox        :string           default("recurring"), not null
#  start_at_jabvox             :datetime
#  subject_jabvox              :string           default(""), not null
#  template_language_jabvox    :string
#  template_name_jabvox        :string
#  template_params_jabvox      :jsonb            not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  created_by_id               :bigint
#  email_template_id           :bigint
#  inbox_id                    :bigint
#  sms_provider_id             :bigint
#  task_id                     :bigint           not null
#
# Indexes
#
#  idx_on_active_jabvox_next_run_at_jabvox_c67e09e205       (active_jabvox,next_run_at_jabvox)
#  index_jabvox_task_automations_on_account_id              (account_id)
#  index_jabvox_task_automations_on_account_id_and_task_id  (account_id,task_id)
#  index_jabvox_task_automations_on_created_by_id           (created_by_id)
#  index_jabvox_task_automations_on_email_template_id       (email_template_id)
#  index_jabvox_task_automations_on_inbox_id                (inbox_id)
#  index_jabvox_task_automations_on_sms_provider_id         (sms_provider_id)
#  index_jabvox_task_automations_on_task_id                 (task_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (email_template_id => jabvox_email_templates.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sms_provider_id => jabvox_sms_providers.id)
#  fk_rails_...  (task_id => jabvox_tasks.id)
#
class JabvoxTaskAutomation < ApplicationRecord
  include Jabvox::AccountScopedReferences

  self.table_name = 'jabvox_task_automations'

  # `inbox` enviaba texto libre, que WhatsApp solo acepta dentro de la ventana de 24h. Una
  # automatización programada dispara casi siempre fuera de ella, así que el envío por
  # WhatsApp es por plantilla aprobada.
  CHANNELS = %w[email sms whatsapp_template].freeze
  # Minuto y hora permiten recordatorios intradía ("cada 2 horas"), que antes obligaban a
  # crear una automatización por repetición.
  UNITS = %w[minute hour day week month].freeze
  # `recurring`: cada X desde que se crea, hasta la fecha/tope que se configure.
  # `before_due`: N avisos cada X ANTES del vencimiento de la tarea. La tarea pone el final,
  # así que no hay que configurar fecha de fin ni arriesgarse a un ciclo infinito.
  SCHEDULE_MODES = %w[recurring before_due].freeze
  RECIPIENT_KINDS = %w[lead assignees lead_contacts manual].freeze

  belongs_to :account
  belongs_to :task, class_name: 'JabvoxTask'
  belongs_to :email_template, class_name: 'JabvoxEmailTemplate', optional: true
  belongs_to :inbox, optional: true
  belongs_to :sms_provider, class_name: 'JabvoxSmsProvider', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :runs, -> { order(run_at_jabvox: :desc) }, class_name: 'JabvoxTaskAutomationRun',
                                                      foreign_key: :automation_id,
                                                      inverse_of: :automation, dependent: :destroy

  # Misma razón que en las automatizaciones de etapa: las FKs salientes viajan en el
  # formulario y hay que comprobar que son de esta cuenta.
  validates_account_scope :inbox, :email_template, :sms_provider

  validates :channel_jabvox, inclusion: { in: CHANNELS }
  validate :whatsapp_template_complete, if: -> { channel_jabvox == 'whatsapp_template' }
  validates :interval_unit_jabvox, inclusion: { in: UNITS }
  validates :interval_count_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 365 }
  validates :max_runs_jabvox, numericality: { greater_than: 0, allow_nil: true }
  validates :schedule_mode_jabvox, inclusion: { in: SCHEDULE_MODES }
  validate :before_due_is_schedulable, if: :before_due?
  # El mapeo responsable->contacto solo puede apuntar a contactos de ESTA cuenta
  # (seguridad: evita referenciar contactos de otra cuenta vía el payload).
  validate :assignee_contact_map_belongs_to_account

  # Due automations exclude tasks that are already done: completing a task stops
  # its recurring automations from firing (without deactivating them, so they
  # resume if the task is reopened).
  scope :due, lambda { |now = Time.current|
    joins(:task)
      .where(active_jabvox: true)
      .where(next_run_at_jabvox: ..now)
      .where(jabvox_tasks: { deleted_at_jabvox: nil })
      .where.not(jabvox_tasks: { status_jabvox: 'done' })
  }

  before_validation :set_initial_schedule, on: :create

  # Parsed recipient kinds (e.g. ["lead", "assignees"]).
  def recipient_kinds
    recipients_jabvox.to_s.split(',').map(&:strip).reject(&:blank?) & RECIPIENT_KINDS
  end

  # Contacto mapeado a un responsable (assignee/User), para enviarle la plantilla de
  # WhatsApp (que necesita un contacto real). Devuelve nil si no hay mapeo o el contacto
  # ya no existe en la cuenta. Scopeado a @account por seguridad.
  def assignee_contact_for(user_id)
    contact_id = (assignee_contact_map_jabvox || {})[user_id.to_s]
    return nil if contact_id.blank?

    account.contacts.find_by(id: contact_id)
  end

  # Step length for one recurrence as an ActiveSupport::Duration.
  def interval_duration
    count = interval_count_jabvox.to_i
    case interval_unit_jabvox
    when 'minute' then count.minutes
    when 'hour' then count.hours
    when 'week' then count.weeks
    when 'month' then count.months
    else count.days
    end
  end

  # Advance the schedule after a dispatch: bump counters and compute the next run,
  # deactivating when the schedule is exhausted.
  def mark_ran!(now = Time.current)
    next_run = (next_run_at_jabvox || now) + interval_duration
    runs = runs_count_jabvox + 1
    finished = finished?(next_run, runs)
    update!(
      last_run_at_jabvox: now,
      runs_count_jabvox: runs,
      next_run_at_jabvox: finished ? nil : next_run,
      active_jabvox: finished ? false : active_jabvox
    )
  end

  def before_due?
    schedule_mode_jabvox == 'before_due'
  end

  # Se agota por fecha o por cantidad, lo que ocurra primero. En modo `before_due` también
  # termina al alcanzar el vencimiento: avisar "antes" después de la fecha no tiene sentido,
  # y es lo que impedía que una tanda de avisos terminara sola.
  def finished?(next_run, runs)
    past_end?(next_run) || runs_exhausted?(runs) || past_due?(next_run)
  end

  def past_end?(next_run)
    end_at_jabvox.present? && next_run > end_at_jabvox
  end

  def runs_exhausted?(runs)
    max_runs_jabvox.to_i.positive? && runs >= max_runs_jabvox
  end

  # Avisar "antes del vencimiento" después de la fecha no tiene sentido.
  def past_due?(next_run)
    return false unless before_due?

    due = task&.due_at_jabvox
    due.present? && next_run > due
  end

  private

  def set_initial_schedule
    self.start_at_jabvox ||= Time.current
    self.next_run_at_jabvox ||= before_due? ? first_before_due_run : start_at_jabvox
  end

  # Primer aviso de la tanda: tantos intervalos antes del vencimiento como avisos se pidan.
  # Con 3 avisos cada 2h y vencimiento a las 18:00 → 12:00, 14:00 y 16:00.
  def first_before_due_run
    due = task&.due_at_jabvox
    return start_at_jabvox if due.blank?

    due - (interval_duration * runs_planned)
  end

  def runs_planned
    [max_runs_jabvox.to_i, 1].max
  end

  def before_due_is_schedulable
    errors.add(:max_runs_jabvox, 'indica cuántos avisos quieres enviar') unless max_runs_jabvox.to_i.positive?
    errors.add(:base, 'la tarea necesita fecha de vencimiento para avisar antes') if task&.due_at_jabvox.blank?
  end

  def whatsapp_template_complete
    errors.add(:inbox, 'debes elegir la bandeja de WhatsApp') if inbox_id.blank?
    errors.add(:template_name_jabvox, 'debes elegir la plantilla') if template_name_jabvox.blank?
    # Por WhatsApp solo sale la plantilla. Un cuerpo escrito a mano aquí no se enviaría
    # nunca, así que guardarlo solo serviría para hacer creer que sí.
    self.body_jabvox = nil
  end

  # El mapeo { "<user_id>" => <contact_id> } solo puede referenciar contactos de esta
  # cuenta. Se ignoran entradas vacías; cualquier contact_id que no sea de la cuenta
  # invalida el registro (defensa anti cross-account vía payload).
  def assignee_contact_map_belongs_to_account
    map = assignee_contact_map_jabvox
    return if map.blank?
    return errors.add(:assignee_contact_map_jabvox, 'formato inválido') unless map.is_a?(Hash)

    contact_ids = map.values.reject(&:blank?).map(&:to_i).uniq
    return if contact_ids.empty?

    found = account.contacts.where(id: contact_ids).count
    return if found == contact_ids.size

    errors.add(:assignee_contact_map_jabvox, 'contiene contactos que no son de esta cuenta')
  end
end
