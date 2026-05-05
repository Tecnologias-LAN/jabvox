# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_affiliates
#
#  id           :bigint           not null, primary key
#  account_code :string           not null
#  active       :boolean          default(TRUE), not null
#  auth_token   :string           not null
#  name         :string           not null
#  portal_slug  :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  account_id   :bigint           not null
#
# Indexes
#
#  index_jabvox_affiliates_on_account_code           (account_code) UNIQUE
#  index_jabvox_affiliates_on_account_id             (account_id)
#  index_jabvox_affiliates_on_account_id_and_active  (account_id,active)
#  index_jabvox_affiliates_on_auth_token             (auth_token) UNIQUE
#  index_jabvox_affiliates_on_portal_slug            (portal_slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
#  id           :bigint           not null, primary key
#  account_id   :bigint           not null
#  name         :string           not null
#  account_code :string           not null
#  auth_token   :string           not null
#  active       :boolean          default(TRUE), not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null

class JabvoxAffiliate < ApplicationRecord
  self.table_name = 'jabvox_affiliates'

  encrypts :account_code, deterministic: true
  encrypts :auth_token, deterministic: true

  belongs_to :account
  has_many :jabvox_leads, dependent: :nullify
  has_many :jabvox_affiliate_imports, dependent: :destroy
  has_many :jabvox_affiliate_ip_whitelists, dependent: :destroy

  validates :name, presence: true
  validates :account_code, presence: true, uniqueness: true
  validates :auth_token, presence: true, uniqueness: true
  validates :portal_slug, presence: true, uniqueness: true
  validates :account_id, presence: true

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(created_at: :desc) }

  before_validation :generate_credentials, on: :create

  def regenerate_account_code!
    update!(account_code: self.class.generate_account_code)
  end

  def regenerate_auth_token!
    update!(auth_token: self.class.generate_auth_token)
  end

  def regenerate_portal_slug!
    update!(portal_slug: self.class.generate_portal_slug)
  end

  def self.generate_account_code
    "ACC-#{Time.now.to_i * 1000 + rand(999)}-#{SecureRandom.alphanumeric(8).upcase}"
  end

  def self.generate_auth_token
    SecureRandom.alphanumeric(32)
  end

  def self.generate_portal_slug
    loop do
      slug = SecureRandom.alphanumeric(8).downcase
      break slug unless exists?(portal_slug: slug)
    end
  end

  private

  def generate_credentials
    self.account_code ||= self.class.generate_account_code
    self.auth_token ||= self.class.generate_auth_token
    self.portal_slug ||= self.class.generate_portal_slug
  end
end
