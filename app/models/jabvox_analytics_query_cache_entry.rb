# Durable query result cache (Redis holds hot/small results; this table holds large/durable ones).
# Class name avoids the awkward pluralisation of the `jabvox_analytics_query_cache` table.
# == Schema Information
#
# Table name: jabvox_analytics_query_cache
#
#  id                :bigint           not null, primary key
#  cache_key_jabvox  :string           not null
#  expires_at_jabvox :datetime         not null
#  result_jabvox     :jsonb            not null
#  row_count_jabvox  :integer          default(0), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  data_source_id    :bigint
#
# Indexes
#
#  idx_on_account_id_cache_key_jabvox_8c331ff9f1            (account_id,cache_key_jabvox) UNIQUE
#  index_jabvox_analytics_query_cache_on_account_id         (account_id)
#  index_jabvox_analytics_query_cache_on_data_source_id     (data_source_id)
#  index_jabvox_analytics_query_cache_on_expires_at_jabvox  (expires_at_jabvox)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (data_source_id => jabvox_analytics_data_sources.id)
#
class JabvoxAnalyticsQueryCacheEntry < ApplicationRecord
  self.table_name = 'jabvox_analytics_query_cache'

  belongs_to :account
  belongs_to :data_source, class_name: 'JabvoxAnalyticsDataSource', optional: true

  validates :cache_key_jabvox, presence: true, uniqueness: { scope: :account_id }
  validates :expires_at_jabvox, presence: true

  scope :fresh, -> { where('expires_at_jabvox > ?', Time.current) }
  scope :expired, -> { where(expires_at_jabvox: ..Time.current) }
end
