# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_calendar_events
#
#  id                  :bigint           not null, primary key
#  all_day             :boolean          default(FALSE), not null
#  color               :string           default("#3B82F6")
#  description         :text
#  end_at              :datetime         not null
#  event_type          :integer          default("reminder"), not null
#  note                :text
#  remind_before_day   :boolean          default(FALSE), not null
#  remind_before_hour  :boolean          default(FALSE), not null
#  start_at            :datetime         not null
#  status              :integer          default("pending"), not null
#  title               :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  branch_id           :bigint
#  contact_id          :bigint
#  created_by_id       :bigint
#  jabvox_task_id      :bigint
#  recurrence_group_id :string
#  user_id             :bigint           not null
#
# Indexes
#
#  index_jabvox_calendar_events_on_account_id               (account_id)
#  index_jabvox_calendar_events_on_account_id_and_start_at  (account_id,start_at)
#  index_jabvox_calendar_events_on_account_id_and_user_id   (account_id,user_id)
#  index_jabvox_calendar_events_on_branch_id                (branch_id)
#  index_jabvox_calendar_events_on_contact_id               (contact_id)
#  index_jabvox_calendar_events_on_created_by_id            (created_by_id)
#  index_jabvox_calendar_events_on_jabvox_task_id           (jabvox_task_id)
#  index_jabvox_calendar_events_on_recurrence_group_id      (recurrence_group_id)
#  index_jabvox_calendar_events_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_jabvox_calendar_events_contact  (contact_id => contacts.id)
#  fk_rails_...                       (account_id => accounts.id)
#  fk_rails_...                       (branch_id => jabvox_branches.id)
#  fk_rails_...                       (created_by_id => users.id)
#  fk_rails_...                       (jabvox_task_id => jabvox_tasks.id)
#  fk_rails_...                       (user_id => users.id)
#

class JabvoxCalendarEvent < ApplicationRecord
  belongs_to :account
  belongs_to :branch, class_name: 'JabvoxBranch', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :user
  belongs_to :contact, optional: true
  belongs_to :jabvox_task, class_name: 'JabvoxTask', optional: true, inverse_of: :calendar_events
  has_many :jabvox_calendar_event_reminders, dependent: :destroy
  has_many :jabvox_calendar_event_participants, dependent: :destroy
  has_many :participant_users, through: :jabvox_calendar_event_participants, source: :user
  has_many :participant_external_people, through: :jabvox_calendar_event_participants, source: :external_person

  enum :event_type, { reminder: 0, appointment: 1, task: 2 }
  enum :status, { pending: 0, done: 1, cancelled: 2 }

  validates :title, presence: true, length: { maximum: 255 }
  validates :start_at, presence: true
  validates :end_at, presence: true
  validate :end_after_start
  validate :references_belong_to_account

  scope :ordered, -> { order(start_at: :asc) }
  scope :for_range, ->(from, to) { where(start_at: from..to) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  # Events the given user owns OR is a participant of (used for the "my calendar" filter).
  scope :visible_to_user, lambda { |user_id|
    left_joins(:jabvox_calendar_event_participants)
      .where('jabvox_calendar_events.user_id = :uid OR jabvox_calendar_event_participants.user_id = :uid', uid: user_id)
      .distinct
  }

  private

  # El fin va después del inicio también en los eventos de todo el día: excluirlos dejaba
  # pasar rangos invertidos, que es justo lo que producía el formulario cuando guardaba la
  # hora residual en un evento marcado como de todo el día.
  # El contacto y el usuario tienen que ser de la misma cuenta que el evento: `contact_id`
  # llega en el formulario y sin validarlo se podía enlazar el contacto de otra cuenta,
  # que el serializador devolvía con nombre y email.
  def references_belong_to_account
    return if account_id.blank?

    errors.add(:contact, :invalid, message: 'no pertenece a esta cuenta') if foreign_contact?
    errors.add(:branch, :invalid, message: 'no pertenece a esta cuenta') if foreign_branch?
    errors.add(:jabvox_task, :invalid, message: 'no pertenece a esta cuenta') if foreign_task?
    errors.add(:user, :invalid, message: 'no pertenece a esta cuenta') if foreign_user?
  end

  def foreign_contact?
    contact.present? && contact.account_id != account_id
  end

  def foreign_branch?
    branch.present? && branch.account_id != account_id
  end

  # Hoy no llega por la API, pero la asociación existe: validarlo ahora evita que añadir
  # `jabvox_task_id` a los params permitidos abra una fuga sin que nadie lo note.
  def foreign_task?
    jabvox_task.present? && jabvox_task.account_id != account_id
  end

  # Un usuario pertenece a varias cuentas, así que la comprobación va por account_users.
  def foreign_user?
    user_id.present? && !AccountUser.exists?(account_id: account_id, user_id: user_id)
  end

  # Los eventos con hora exigen fin posterior al inicio. Los de todo el día se comparan
  # por FECHA: uno que ocupa un solo día puede tener el mismo instante en ambos extremos,
  # y compararlos como instantes lo rechazaría siendo válido.
  def end_after_start
    return unless start_at && end_at

    if all_day
      errors.add(:end_at, 'must not end before the start date') if end_at.to_date < start_at.to_date
    elsif end_at <= start_at
      errors.add(:end_at, 'must be after start time')
    end
  end
end
