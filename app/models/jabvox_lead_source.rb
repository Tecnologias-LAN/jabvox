# An external database connection used to import leads. Credentials are encrypted
# and never exposed to the frontend (the serializer returns has_password only).
# All access to the external DB is read-only and SSRF-guarded.
# == Schema Information
#
# Table name: jabvox_lead_sources
#
#  id                           :bigint           not null, primary key
#  allow_private_network_jabvox :boolean          default(FALSE), not null
#  database_jabvox              :string
#  engine_jabvox                :string           not null
#  external_id_column_jabvox    :string
#  field_mapping_jabvox         :jsonb            not null
#  filters_jabvox               :jsonb            not null
#  host_jabvox                  :string
#  last_sync_result_jabvox      :jsonb            not null
#  last_synced_at_jabvox        :datetime
#  last_tested_at_jabvox        :datetime
#  name_jabvox                  :string           not null
#  password_jabvox              :text
#  phone_prefix_jabvox          :string           default(""), not null
#  port_jabvox                  :integer
#  query_timeout_ms_jabvox      :integer          default(30000), not null
#  related_tables_jabvox        :jsonb            not null
#  ssl_mode_jabvox              :string           default("prefer"), not null
#  status_jabvox                :string           default("untested"), not null
#  table_jabvox                 :string
#  username_jabvox              :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :bigint           not null
#  created_by_id                :bigint
#
# Indexes
#
#  index_jabvox_lead_sources_on_account_id                  (account_id)
#  index_jabvox_lead_sources_on_account_id_and_name_jabvox  (account_id,name_jabvox) UNIQUE
#  index_jabvox_lead_sources_on_created_by_id               (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxLeadSource < ApplicationRecord
  self.table_name = 'jabvox_lead_sources'

  # Only network engines (SQLite has no remote import use case here).
  ENGINES = %w[postgresql mysql mariadb].freeze
  DEFAULT_PORTS = { 'postgresql' => 5432, 'mysql' => 3306, 'mariadb' => 3306 }.freeze

  encrypts :password_jabvox if Jabvox.encryption_configured?

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :records, class_name: 'JabvoxLeadSourceRecord', foreign_key: :lead_source_id,
                     inverse_of: :lead_source, dependent: :delete_all

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :engine_jabvox, inclusion: { in: ENGINES }
  validates :host_jabvox, presence: true
  validates :database_jabvox, presence: true
  validates :query_timeout_ms_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 600_000 }
  validates :port_jabvox, numericality: { greater_than: 0, less_than_or_equal_to: 65_535 }, allow_nil: true

  def effective_port
    port_jabvox.presence || DEFAULT_PORTS[engine_jabvox.to_s]
  end

  # --- Compatibility shims so the analytics DB adapters can be reused as-is ---
  # Import needs the whole table, so use a high row cap (still bounded).
  def max_rows_jabvox
    1_000_000
  end

  # No SQLite engine here; adapters reference this only for the sqlite adapter.
  def sqlite_path_jabvox
    nil
  end

  def sqlite?
    false
  end
end
