# == Schema Information
#
# Table name: jabvox_whatsapp_template_logs
#
#  id                          :bigint           not null, primary key
#  action                      :string           not null
#  description                 :text
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  jabvox_whatsapp_template_id :bigint           not null
#  user_id                     :bigint
#
# Indexes
#
#  idx_on_jabvox_whatsapp_template_id_476ec4a376      (jabvox_whatsapp_template_id)
#  index_jabvox_whatsapp_template_logs_on_account_id  (account_id)
#  index_jabvox_whatsapp_template_logs_on_action      (action)
#  index_jabvox_whatsapp_template_logs_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_whatsapp_template_id => jabvox_whatsapp_templates.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxWhatsappTemplateLog < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_template_logs'

  belongs_to :jabvox_whatsapp_template
  belongs_to :account
  belongs_to :user, optional: true

  ACTIONS = %w[created updated duplicated deleted synced sent_to_meta restored].freeze
end
