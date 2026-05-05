# == Schema Information
#
# Table name: jabvox_field_visibilities
#
#  id         :bigint           not null, primary key
#  can_view   :boolean          default(TRUE), not null
#  field_name :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  idx_jabvox_field_visibility_unique             (account_id,user_id,field_name) UNIQUE
#  index_jabvox_field_visibilities_on_account_id  (account_id)
#  index_jabvox_field_visibilities_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxFieldVisibility < ApplicationRecord
  FIELDS = %w[
    name phone email identification
    company contact_type country city
    social_facebook social_twitter social_linkedin
    social_github social_telegram social_tiktok
  ].freeze

  belongs_to :account
  belongs_to :user

  validates :field_name, inclusion: { in: FIELDS }
  validates :user_id, uniqueness: { scope: [:account_id, :field_name] }
end
