# == Schema Information
#
# Table name: jabvox_whatsapp_template_versions
#
#  id                          :bigint           not null, primary key
#  payload                     :jsonb            not null
#  version                     :integer          default(1), not null
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  created_by_id               :bigint
#  jabvox_whatsapp_template_id :bigint           not null
#
# Indexes
#
#  idx_jabvox_wa_tpl_versions_tpl_version                    (jabvox_whatsapp_template_id,version)
#  idx_on_jabvox_whatsapp_template_id_e80a5f5da4             (jabvox_whatsapp_template_id)
#  index_jabvox_whatsapp_template_versions_on_created_by_id  (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (jabvox_whatsapp_template_id => jabvox_whatsapp_templates.id)
#
class JabvoxWhatsappTemplateVersion < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_template_versions'

  belongs_to :jabvox_whatsapp_template
  belongs_to :created_by, class_name: 'User', optional: true
end
