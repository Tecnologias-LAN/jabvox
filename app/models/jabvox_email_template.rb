# == Schema Information
#
# Table name: jabvox_email_templates
#
#  id         :bigint           not null, primary key
#  active     :boolean          default(TRUE), not null
#  body       :text
#  name       :string           not null
#  subject    :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#
# Indexes
#
#  index_jabvox_email_templates_on_account_id           (account_id)
#  index_jabvox_email_templates_on_account_id_and_name  (account_id,name) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxEmailTemplate < ApplicationRecord
  belongs_to :account

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :subject, presence: true
  validates :body, length: { maximum: 5_000_000 }, allow_nil: true

  scope :active, -> { where(active: true) }

  def self.limit_for(account)
    account.limits['email_templates']&.to_i || 20
  end

  def self.within_limit?(account)
    account.jabvox_email_templates.count < limit_for(account)
  end
end
