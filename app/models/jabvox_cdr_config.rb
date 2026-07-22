# == Schema Information
#
# Table name: jabvox_cdr_configs
#
#  id                   :bigint           not null, primary key
#  analysis_mode        :string           default("manual"), not null
#  last_synced_calldate :datetime
#  last_synced_cursor   :string
#  min_duration_seconds :integer          default(30), not null
#  mysql_database       :string           default("asteriskcdrdb"), not null
#  mysql_host           :string           default(""), not null
#  mysql_password       :text
#  mysql_port           :integer          default(3306), not null
#  mysql_table          :string           default("cdr"), not null
#  mysql_username       :string           default(""), not null
#  recordings_path      :string           default("/var/spool/asterisk/monitor"), not null
#  ssh_host             :string           default(""), not null
#  ssh_password         :text
#  ssh_port             :integer          default(22), not null
#  ssh_username         :string           default(""), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  default_pipeline_id  :bigint
#
# Indexes
#
#  index_jabvox_cdr_configs_on_account_id           (account_id) UNIQUE
#  index_jabvox_cdr_configs_on_default_pipeline_id  (default_pipeline_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (default_pipeline_id => jabvox_cdr_pipelines.id)
#
class JabvoxCdrConfig < ApplicationRecord
  self.table_name = 'jabvox_cdr_configs'

  ANALYSIS_MODES = %w[manual auto_all auto_min_duration].freeze

  belongs_to :account
  belongs_to :default_pipeline, class_name: 'JabvoxCdrPipeline', optional: true

  encrypts :mysql_password if Jabvox.encryption_configured?
  encrypts :ssh_password if Jabvox.encryption_configured?

  validates :mysql_host, presence: true
  validates :mysql_username, presence: true
  validates :mysql_database, presence: true
  validates :mysql_table, presence: true
  validates :mysql_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65_535 }
  validates :ssh_port, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 65_535 }
  validates :analysis_mode, inclusion: { in: ANALYSIS_MODES }
  validates :min_duration_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  def recordings_configured?
    ssh_host.present? && ssh_username.present?
  end
end
