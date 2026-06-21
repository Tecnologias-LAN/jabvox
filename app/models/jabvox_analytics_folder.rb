# Organises dashboards into a tree (self-referential parent).
# == Schema Information
#
# Table name: jabvox_analytics_folders
#
#  id              :bigint           not null, primary key
#  name_jabvox     :string           not null
#  position_jabvox :integer          default(0), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  created_by_id   :bigint
#  parent_id       :bigint
#
# Indexes
#
#  index_jabvox_analytics_folders_on_account_id                (account_id)
#  index_jabvox_analytics_folders_on_account_id_and_parent_id  (account_id,parent_id)
#  index_jabvox_analytics_folders_on_created_by_id             (created_by_id)
#  index_jabvox_analytics_folders_on_parent_id                 (parent_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (parent_id => jabvox_analytics_folders.id)
#
class JabvoxAnalyticsFolder < ApplicationRecord
  self.table_name = 'jabvox_analytics_folders'

  belongs_to :account
  belongs_to :parent, class_name: 'JabvoxAnalyticsFolder', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  has_many :children, class_name: 'JabvoxAnalyticsFolder', foreign_key: :parent_id,
                      dependent: :destroy, inverse_of: :parent
  has_many :dashboards, class_name: 'JabvoxAnalyticsDashboard', foreign_key: :folder_id,
                        dependent: :nullify, inverse_of: :folder

  validates :name_jabvox, presence: true
  validate :parent_not_self

  scope :roots, -> { where(parent_id: nil) }
  scope :ordered, -> { order(:position_jabvox, :name_jabvox) }

  private

  def parent_not_self
    errors.add(:parent_id, 'cannot be itself') if parent_id.present? && parent_id == id
  end
end
