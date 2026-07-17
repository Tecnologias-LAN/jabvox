# A per-account external database that mirrors this account's data in real time.
# The module ONLY writes (INSERT/UPSERT via parameterized statements — no client
# SQL is ever executed). Credentials are encrypted and never exposed to the frontend.
# == Schema Information
#
# Table name: jabvox_export_targets
#
#  id                            :bigint           not null, primary key
#  allow_private_network_jabvox  :boolean          default(FALSE), not null
#  create_missing_columns_jabvox :boolean          default(FALSE), not null
#  database_jabvox               :string
#  enabled_jabvox                :boolean          default(FALSE), not null
#  engine_jabvox                 :string           not null
#  field_mapping_jabvox          :jsonb            not null
#  host_jabvox                   :string
#  last_error_jabvox             :string
#  last_export_at_jabvox         :datetime
#  last_full_sync_at_jabvox      :datetime
#  last_sync_result_jabvox       :jsonb            not null
#  last_tested_at_jabvox         :datetime
#  mode_jabvox                   :string           default("create"), not null
#  name_jabvox                   :string           not null
#  password_jabvox               :text
#  port_jabvox                   :integer
#  query_timeout_ms_jabvox       :integer          default(15000), not null
#  schema_built_at_jabvox        :datetime
#  selected_modules_jabvox       :jsonb            not null
#  ssl_mode_jabvox               :string           default("prefer"), not null
#  status_jabvox                 :string           default("untested"), not null
#  sync_status_jabvox            :string           default("idle"), not null
#  username_jabvox               :string
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  created_by_id                 :bigint
#
# Indexes
#
#  idx_export_targets_one_per_account                         (account_id) UNIQUE
#  index_jabvox_export_targets_on_account_id                  (account_id)
#  index_jabvox_export_targets_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#  index_jabvox_export_targets_on_created_by_id               (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxExportTarget < ApplicationRecord
  self.table_name = 'jabvox_export_targets'

  ENGINES = %w[postgresql mysql mariadb].freeze
  DEFAULT_PORTS = { 'postgresql' => 5432, 'mysql' => 3306, 'mariadb' => 3306 }.freeze

  encrypts :password_jabvox if Jabvox.encryption_configured?

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :jabvox_export_sync_logs, dependent: :delete_all

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :engine_jabvox, inclusion: { in: ENGINES }
  validates :host_jabvox, presence: true
  validates :database_jabvox, presence: true
  validates :query_timeout_ms_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 120_000 }
  validates :port_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 65_535 }, allow_nil: true
  # Golden rule: exactly ONE external database per account, to keep the real-time
  # sync cheap. A second target for the same account is rejected at the model
  # level (belt) and the controller enforces it too (suspenders).
  validate :single_target_per_account, on: :create

  # The single enabled export target for an account (there is one DB per account).
  scope :active, -> { where(enabled_jabvox: true) }

  def effective_port
    port_jabvox.presence || DEFAULT_PORTS[engine_jabvox.to_s]
  end

  # Group keys the customer chose to export. Empty array = export everything the
  # account has enabled. Always stored as an array of strings.
  def selected_modules
    Array(selected_modules_jabvox).map(&:to_s)
  end

  private

  def single_target_per_account
    return if account_id.blank?
    return unless self.class.where(account_id: account_id).where.not(id: id).exists?

    errors.add(:base, 'Solo se permite una base de datos externa por cuenta')
  end
end
