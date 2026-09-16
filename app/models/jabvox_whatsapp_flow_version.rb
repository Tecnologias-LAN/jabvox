# == Schema Information
#
# Table name: jabvox_whatsapp_flow_versions
#
#  id                      :bigint           not null, primary key
#  screens_json            :jsonb            not null
#  version                 :integer          default(1), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  created_by_id           :bigint
#  jabvox_whatsapp_flow_id :bigint           not null
#
# Indexes
#
#  idx_jabvox_wa_flow_versions_flow_version                        (jabvox_whatsapp_flow_id,version)
#  index_jabvox_whatsapp_flow_versions_on_created_by_id            (created_by_id)
#  index_jabvox_whatsapp_flow_versions_on_jabvox_whatsapp_flow_id  (jabvox_whatsapp_flow_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (jabvox_whatsapp_flow_id => jabvox_whatsapp_flows.id)
#
class JabvoxWhatsappFlowVersion < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_flow_versions'

  belongs_to :jabvox_whatsapp_flow
  belongs_to :created_by, class_name: 'User', optional: true

  validates :version, presence: true
end
