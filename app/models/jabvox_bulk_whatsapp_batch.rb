# Audit record of one bulk WhatsApp send: which inbox, whose API token was forwarded, how many
# rows the CSV had, and whether the POST to the n8n webhook succeeded. Shown in the module's
# history view.
# == Schema Information
#
# Table name: jabvox_bulk_whatsapp_batches
#
#  id                       :bigint           not null, primary key
#  access_token_id_jabvox   :bigint
#  attempts_jabvox          :integer          default(0), not null
#  batch_uuid_jabvox        :uuid
#  callback_token_jabvox    :string
#  error_jabvox             :text
#  failed_count_jabvox      :integer          default(0), not null
#  file_name_jabvox         :string           default(""), not null
#  filters_jabvox           :jsonb            not null
#  finished_at_jabvox       :datetime
#  mode_jabvox              :string           default("template"), not null
#  payload_jabvox           :jsonb            not null
#  response_email_jabvox    :string           default(""), not null
#  sent_at_jabvox           :datetime
#  sent_count_jabvox        :integer          default(0), not null
#  source_batch_id_jabvox   :bigint
#  source_type_jabvox       :string
#  status_jabvox            :string           default("pending"), not null
#  template_category_jabvox :string
#  template_language_jabvox :string
#  template_name_jabvox     :string
#  token_expires_at_jabvox  :datetime
#  total_rows_jabvox        :integer          default(0), not null
#  valid_rows_jabvox        :integer          default(0), not null
#  variable_mapping_jabvox  :jsonb            not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :bigint           not null
#  created_by_id            :bigint
#  inbox_id                 :bigint
#  sender_user_id           :bigint
#
# Indexes
#
#  idx_bulk_wa_batches_source_batch                      (source_batch_id_jabvox)
#  idx_bulk_wa_batches_uuid                              (batch_uuid_jabvox) UNIQUE
#  idx_on_account_id_created_at_793a6e41e6               (account_id,created_at)
#  idx_on_account_id_status_jabvox_8e3a4a349f            (account_id,status_jabvox)
#  index_jabvox_bulk_whatsapp_batches_on_account_id      (account_id)
#  index_jabvox_bulk_whatsapp_batches_on_created_by_id   (created_by_id)
#  index_jabvox_bulk_whatsapp_batches_on_inbox_id        (inbox_id)
#  index_jabvox_bulk_whatsapp_batches_on_sender_user_id  (sender_user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (sender_user_id => users.id)
#
class JabvoxBulkWhatsappBatch < ApplicationRecord
  self.table_name = 'jabvox_bulk_whatsapp_batches'

  # `pending`/`sent`/`failed` are the legacy states the delivery job still uses.
  # The wizard/report flow adds the richer per-execution lifecycle:
  #   queued   → job encoló los chunks a n8n
  #   running  → llegando resultados por callback
  #   completed→ todos enviados / partial→ hubo fallidos / failed→ nada salió
  STATUSES = %w[draft pending queued running completed partial failed sent].freeze
  SOURCE_TYPES = %w[csv jabvox].freeze

  belongs_to :account
  belongs_to :inbox, optional: true
  belongs_to :sender_user, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  belongs_to :source_batch, class_name: 'JabvoxBulkWhatsappBatch',
                            foreign_key: :source_batch_id_jabvox, optional: true, inverse_of: false
  has_many :recipients, class_name: 'JabvoxBulkWhatsappRecipient',
                        foreign_key: :bulk_whatsapp_batch_id, dependent: :destroy, inverse_of: :batch

  validates :status_jabvox, inclusion: { in: STATUSES }

  before_create :assign_batch_uuid

  # Recomputes counters and lifecycle status from the recipients' outcomes.
  # Called by the callback controller as results arrive from n8n and by the
  # Meta reconciliation. `final` marks the batch finished (all chunks reported).
  def recalculate_status!(final: false)
    sent = recipients.where(status_jabvox: 'sent').count
    failed = recipients.where(status_jabvox: 'failed').count
    total = recipients.count
    new_status = next_status(sent, failed, total, final)

    terminal = %w[completed partial failed].include?(new_status)
    update!(
      sent_count_jabvox: sent, failed_count_jabvox: failed,
      status_jabvox: new_status,
      finished_at_jabvox: terminal ? (finished_at_jabvox || Time.current) : finished_at_jabvox
    )
    revoke_access_token! if terminal
  end

  # Borra el token efímero del envío en cuanto el batch termina (lo confirma n8n por
  # callback). Así el token no expira a mitad del envío (no tiene expiración por tiempo)
  # y tampoco queda vivo tras terminar. El cleanup job de respaldo lo cubre si el callback
  # final nunca llega.
  def revoke_access_token!
    return if access_token_id_jabvox.blank?

    AccessToken.where(id: access_token_id_jabvox).destroy_all
    # rubocop:disable Rails/SkipsModelValidations
    update_column(:access_token_id_jabvox, nil) # solo limpia el puntero; sin callbacks
    # rubocop:enable Rails/SkipsModelValidations
  end

  private

  def next_status(sent, failed, total, final)
    return 'running' unless final || ((sent + failed) >= total && total.positive?)
    return 'completed' if failed.zero?
    return 'failed' if sent.zero?

    'partial'
  end

  def assign_batch_uuid
    self.batch_uuid_jabvox ||= SecureRandom.uuid
    self.callback_token_jabvox ||= SecureRandom.hex(32)
  end
end
