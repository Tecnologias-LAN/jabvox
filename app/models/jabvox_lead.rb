# == Schema Information
#
# Table name: jabvox_leads
#
#  id                  :bigint           not null, primary key
#  is_sold_jabvox      :boolean          default(FALSE), not null
#  lead_number         :integer          not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  assignee_id         :bigint
#  contact_id          :bigint           not null
#  jabvox_affiliate_id :bigint
#  jabvox_campaign_id  :bigint
#
# Indexes
#
#  index_jabvox_leads_on_account_id                         (account_id)
#  index_jabvox_leads_on_account_id_and_contact_id          (account_id,contact_id) UNIQUE
#  index_jabvox_leads_on_account_id_and_jabvox_campaign_id  (account_id,jabvox_campaign_id)
#  index_jabvox_leads_on_account_id_and_lead_number         (account_id,lead_number) UNIQUE
#  index_jabvox_leads_on_assignee_id                        (assignee_id)
#  index_jabvox_leads_on_contact_id                         (contact_id)
#  index_jabvox_leads_on_is_sold_jabvox                     (is_sold_jabvox)
#  index_jabvox_leads_on_jabvox_affiliate_id                (jabvox_affiliate_id)
#  index_jabvox_leads_on_jabvox_campaign_id                 (jabvox_campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (contact_id => contacts.id)
#  fk_rails_...  (jabvox_affiliate_id => jabvox_affiliates.id)
#  fk_rails_...  (jabvox_campaign_id => jabvox_campaigns.id)
#
class JabvoxLead < ApplicationRecord
  belongs_to :account
  belongs_to :contact
  belongs_to :jabvox_campaign, optional: true
  belongs_to :jabvox_affiliate, optional: true
  belongs_to :assignee, class_name: 'User', optional: true

  validates :contact_id, uniqueness: { scope: :account_id }
  validates :lead_number, presence: true, uniqueness: { scope: :account_id }

  before_validation :assign_lead_number, on: :create

  scope :with_associations, -> { includes(:contact, :jabvox_campaign, :assignee, contact: { contact_inboxes: :inbox }) }
  scope :ordered, -> { order(lead_number: :asc) }

  private

  def assign_lead_number
    return if lead_number.present?

    self.lead_number = (JabvoxLead.where(account_id: account_id).maximum(:lead_number) || 0) + 1
  end
end
