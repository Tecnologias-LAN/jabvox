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
  # 'create' builds our own mirror tables; 'map' writes only into columns that
  # already exist in the customer's DB, per field_mapping_jabvox.
  MODES = %w[create map].freeze

  encrypts :password_jabvox if Jabvox.encryption_configured?

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :engine_jabvox, inclusion: { in: ENGINES }
  validates :mode_jabvox, inclusion: { in: MODES }
  validates :host_jabvox, presence: true
  validates :database_jabvox, presence: true
  validates :query_timeout_ms_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 120_000 }
  validates :port_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 65_535 }, allow_nil: true

  # The single enabled export target for an account (there is one DB per account).
  scope :active, -> { where(enabled_jabvox: true) }

  def effective_port
    port_jabvox.presence || DEFAULT_PORTS[engine_jabvox.to_s]
  end

  def map_mode?
    mode_jabvox.to_s == 'map'
  end

  # Mapping for one mirror table, or nil when the table isn't mapped.
  # Shape: { 'key' => '<customer key column>',
  #          'columns' => { '<jabvox_col>' => '<customer_col>', ... } }
  def mapping_for(table)
    m = (field_mapping_jabvox || {})[table.to_s]
    return nil unless m.is_a?(Hash)

    cols = m['columns']
    return nil unless cols.is_a?(Hash) && cols.present?

    { 'key' => m['key'].to_s.presence, 'columns' => cols }
  end

  # Compatibility shims so the analytics DB adapters (connection_params) work as-is.
  def max_rows_jabvox
    1
  end

  def sqlite_path_jabvox
    nil
  end

  def sqlite?
    false
  end
end
