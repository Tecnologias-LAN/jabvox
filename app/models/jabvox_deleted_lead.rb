# A soft-deleted lead kept in the trash so it can be restored from super admin
# within the retention window. After RETENTION_DAYS a scheduled job purges it.
# == Schema Information
#
# Table name: jabvox_deleted_leads
#
#  id                      :bigint           not null, primary key
#  deleted_at_jabvox       :datetime         not null
#  external_id_jabvox      :string
#  original_lead_id_jabvox :bigint
#  restored_at_jabvox      :datetime
#  snapshot_jabvox         :jsonb            not null
#  source_name_jabvox      :string
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  deleted_by_id           :bigint
#
# Indexes
#
#  index_jabvox_deleted_leads_on_account_id                        (account_id)
#  index_jabvox_deleted_leads_on_account_id_and_deleted_at_jabvox  (account_id,deleted_at_jabvox)
#  index_jabvox_deleted_leads_on_deleted_by_id                     (deleted_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (deleted_by_id => users.id)
#
class JabvoxDeletedLead < ApplicationRecord
  self.table_name = 'jabvox_deleted_leads'

  RETENTION_DAYS = 30

  belongs_to :account
  belongs_to :deleted_by, class_name: 'User', optional: true

  scope :active, -> { where(restored_at_jabvox: nil) }
  scope :restorable, -> { active.where(deleted_at_jabvox: RETENTION_DAYS.days.ago..) }
  scope :expired, -> { active.where(deleted_at_jabvox: ...RETENTION_DAYS.days.ago) }

  def restorable?
    restored_at_jabvox.nil? && deleted_at_jabvox >= RETENTION_DAYS.days.ago
  end

  def expires_at
    deleted_at_jabvox + RETENTION_DAYS.days
  end
end
