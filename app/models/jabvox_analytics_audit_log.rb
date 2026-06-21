# Append-only audit trail for the Analytics module. Metadata is sanitized upstream
# (never raw passwords or secret SQL). Records are written via Jabvox::Analytics::AuditService.
# == Schema Information
#
# Table name: jabvox_analytics_audit_logs
#
#  id                    :bigint           not null, primary key
#  action_jabvox         :string           not null
#  auditable_id_jabvox   :bigint
#  auditable_type_jabvox :string
#  ip_address_jabvox     :string
#  metadata_jabvox       :jsonb            not null
#  result_jabvox         :string           not null
#  user_agent_jabvox     :string
#  created_at            :datetime         not null
#  account_id            :bigint           not null
#  user_id               :bigint
#
# Indexes
#
#  idx_jabvox_analytics_audit_auditable                            (account_id,auditable_type_jabvox,auditable_id_jabvox)
#  idx_on_account_id_action_jabvox_a1695cd477                      (account_id,action_jabvox)
#  index_jabvox_analytics_audit_logs_on_account_id                 (account_id)
#  index_jabvox_analytics_audit_logs_on_account_id_and_created_at  (account_id,created_at)
#  index_jabvox_analytics_audit_logs_on_user_id                    (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxAnalyticsAuditLog < ApplicationRecord
  self.table_name = 'jabvox_analytics_audit_logs'

  # No updated_at column: this table is append-only.
  self.record_timestamps = false

  RESULTS = %w[success failure rejected].freeze

  belongs_to :account
  belongs_to :user, optional: true

  validates :action_jabvox, presence: true
  validates :result_jabvox, inclusion: { in: RESULTS }

  before_validation :stamp_created_at, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :for_action, ->(action) { where(action_jabvox: action) }

  private

  def stamp_created_at
    self.created_at ||= Time.current
  end
end
