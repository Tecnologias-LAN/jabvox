# frozen_string_literal: true

# Mensaje del "Chat Aprovisionamiento" de una cuenta: la conversación entre un usuario
# (con permiso) y el Hermes Provisioner de esa cuenta, donde se le pide crear MCPs
# (analytics, reportes, etc.) o aprovisionar por primera vez su Hermes/ContextForge.
#
# Guarda quién pidió cada cosa (user_id) para auditoría y para gating por permisos.
#
# == Schema Information
#
# Table name: jabvox_provisioning_chat_messages
#
#  id            :bigint           not null, primary key
#  content       :text
#  metadata      :jsonb            not null
#  role          :string           not null
#  status_jabvox :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  session_id    :string           not null
#  user_id       :bigint           not null
#
# Indexes
#
#  idx_jabvox_prov_chat_on_account_session_created        (account_id,session_id,created_at)
#  idx_jabvox_prov_chat_on_session_status                 (session_id,status_jabvox)
#  idx_on_account_id_created_at_0050c7615e                (account_id,created_at)
#  index_jabvox_provisioning_chat_messages_on_account_id  (account_id)
#  index_jabvox_provisioning_chat_messages_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxProvisioningChatMessage < ApplicationRecord
  belongs_to :account
  belongs_to :user

  ROLES = %w[user assistant system].freeze

  validates :role, inclusion: { in: ROLES }
  validates :session_id, presence: true
  # Estado del turno: permite saber al volver al chat si sigue en curso, si quedó esperando
  # una aprobación o si terminó. nil = mensajes anteriores a la columna.
  STATUSES = %w[streaming waiting_approval completed interrupted failed].freeze
  validates :status_jabvox, inclusion: { in: STATUSES }, allow_nil: true

  scope :recent_first, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }
  scope :in_session, ->(session_id) { where(session_id: session_id) }

  after_update_commit :notify_user_when_approval_needed,
                      if: -> { role == 'assistant' && saved_change_to_status_jabvox? }

  def push_event_data
    { id: id, session_id: session_id, status: status_jabvox }
  end

  # Resumen de las conversaciones de una cuenta para la lista lateral: una fila por
  # session_id con su último mensaje. El título se deriva del primer mensaje del usuario
  # (no hay campo title), igual que hace el Chat IA.
  def self.sessions_for(account_id, limit: 50)
    where(account_id: account_id)
      .group(:session_id)
      .pluck(Arel.sql('session_id, MAX(created_at), COUNT(*)'))
      .sort_by { |row| row[1] }
      .reverse
      .first(limit)
      .map { |sid, last_at, count| { session_id: sid, last_at: last_at, messages_count: count } }
  end

  private

  def notify_user_when_approval_needed
    return unless status_jabvox == 'waiting_approval'

    Jabvox::ModuleNotificationService.create!(
      account: account,
      user: user,
      type: :jabvox_ai_provisioning_approval,
      actor: self,
      title: 'El chat IA requiere tu aprobación',
      body: 'Hay una acción de aprovisionamiento pendiente de autorización.',
      path: "/app/accounts/#{account_id}/jabvox/provisioning-chat"
    )
  end
end
