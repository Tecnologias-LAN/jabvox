# == Schema Information
#
# Table name: jabvox_form_configs
#
#  id                 :bigint           not null, primary key
#  acme_account_key   :text
#  base_url_jabvox    :string           default("")
#  max_forms_jabvox   :integer          default(10), not null
#  ssl_cert           :text
#  ssl_error          :string(500)
#  ssl_expires_at     :datetime
#  ssl_key            :text
#  ssl_provisioned_at :datetime
#  ssl_status         :string           default("none"), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  index_jabvox_form_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxFormConfig < ApplicationRecord
  self.table_name = 'jabvox_form_configs'

  SSL_STATUSES = %w[none provisioning active failed].freeze

  belongs_to :account

  validates :max_forms_jabvox, numericality: { only_integer: true, greater_than: 0 }
  validates :ssl_status, inclusion: { in: SSL_STATUSES }

  def ssl_active?
    ssl_status == 'active' && ssl_expires_at&.future?
  end

  def ssl_expiring_soon?
    ssl_active? && ssl_expires_at < 30.days.from_now
  end

  def provisioning_locked?
    ssl_status == 'provisioning' && updated_at > 10.minutes.ago
  end
end
