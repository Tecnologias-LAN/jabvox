class AddJabvoxAffiliateIdToJabvoxLeads < ActiveRecord::Migration[7.0]
  def change
    add_reference :jabvox_leads, :jabvox_affiliate, foreign_key: true, null: true, index: true
  end
end
