# An external database connection an account can query read-only.
# Credentials (password, ssl_ca) are AES-256-GCM encrypted via ActiveRecord::Encryption.
# == Schema Information
#
# Table name: jabvox_analytics_data_sources
#
#  id                           :bigint           not null, primary key
#  allow_private_network_jabvox :boolean          default(FALSE), not null
#  database_jabvox              :string
#  engine_jabvox                :string           not null
#  host_jabvox                  :string
#  last_tested_at_jabvox        :datetime
#  max_rows_jabvox              :integer          default(1000), not null
#  name_jabvox                  :string           not null
#  options_jabvox               :jsonb            not null
#  password_jabvox              :text
#  port_jabvox                  :integer
#  query_timeout_ms_jabvox      :integer          default(30000), not null
#  sqlite_path_jabvox           :string
#  ssl_ca_jabvox                :text
#  ssl_mode_jabvox              :string           default("prefer"), not null
#  status_jabvox                :string           default("untested"), not null
#  username_jabvox              :string
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  account_id                   :bigint           not null
#  created_by_id                :bigint
#
# Indexes
#
#  idx_on_account_id_name_jabvox_14bc87f57e              (account_id,name_jabvox) UNIQUE
#  index_jabvox_analytics_data_sources_on_account_id     (account_id)
#  index_jabvox_analytics_data_sources_on_created_by_id  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxAnalyticsDataSource < ApplicationRecord
  self.table_name = 'jabvox_analytics_data_sources'

  ENGINES = %w[postgresql mysql mariadb sqlite].freeze
  STATUSES = %w[untested ok error].freeze
  DEFAULT_PORTS = { 'postgresql' => 5432, 'mysql' => 3306, 'mariadb' => 3306 }.freeze

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :data_source_permissions, class_name: 'JabvoxAnalyticsDataSourcePermission',
                                     foreign_key: :data_source_id, dependent: :destroy, inverse_of: :data_source
  has_many :widgets, class_name: 'JabvoxAnalyticsDashboardWidget',
                     foreign_key: :data_source_id, dependent: :nullify, inverse_of: :data_source
  # Cached query results are disposable; drop them with the data source so
  # deletion doesn't fail on the FK.
  has_many :query_cache_entries, class_name: 'JabvoxAnalyticsQueryCacheEntry',
                                 foreign_key: :data_source_id, dependent: :delete_all, inverse_of: :data_source

  encrypts :password_jabvox if Jabvox.encryption_configured?
  encrypts :ssl_ca_jabvox if Jabvox.encryption_configured?

  validates :name_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :engine_jabvox, inclusion: { in: ENGINES }
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :max_rows_jabvox, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 1_000_000 }
  validates :query_timeout_ms_jabvox, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 600_000 }
  validates :port_jabvox, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65_535 }, allow_nil: true
  validates :database_jabvox, presence: true, unless: :sqlite?
  validates :host_jabvox, presence: true, unless: :sqlite?
  validates :sqlite_path_jabvox, presence: true, if: :sqlite?

  scope :ok, -> { where(status_jabvox: 'ok') }

  def sqlite?
    engine_jabvox == 'sqlite'
  end

  def effective_port
    port_jabvox.presence || DEFAULT_PORTS[engine_jabvox]
  end
end
