# == Schema Information
#
# Table name: access_tokens
#
#  id         :bigint           not null, primary key
#  expires_at :datetime
#  owner_type :string
#  token      :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  owner_id   :bigint
#
# Indexes
#
#  index_access_tokens_on_expires_at               (expires_at)
#  index_access_tokens_on_owner_type_and_owner_id  (owner_type,owner_id)
#  index_access_tokens_on_token                    (token) UNIQUE
#

class AccessToken < ApplicationRecord
  has_secure_token :token
  belongs_to :owner, polymorphic: true

  # Tokens with a nil expires_at never expire (regular user/bot tokens). Only short-lived
  # tokens (e.g. the 30-minute Bulk WhatsApp token) set expires_at; once it passes the token
  # must be treated as invalid everywhere it is authenticated.
  scope :active, -> { where('expires_at IS NULL OR expires_at > ?', Time.current) }
  scope :expired, -> { where('expires_at IS NOT NULL AND expires_at <= ?', Time.current) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end
end
