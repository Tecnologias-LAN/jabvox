# Liga el Hermes Aprovisionador global a una cuenta. Cada cuenta ligada ve el "Chat
# Aprovisionador" para pedirle cosas (crear su propio Hermes, etc.). Una cuenta = un link.
# == Schema Information
#
# Table name: jabvox_hermes_provisioner_links
#
#  id                    :bigint           not null, primary key
#  status_jabvox         :string           default("linked"), not null
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  account_id            :bigint           not null
#  hermes_provisioner_id :bigint           not null
#
# Indexes
#
#  index_jabvox_hermes_provisioner_links_on_account_id             (account_id) UNIQUE
#  index_jabvox_hermes_provisioner_links_on_hermes_provisioner_id  (hermes_provisioner_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (hermes_provisioner_id => jabvox_hermes_provisioners.id)
#
class JabvoxHermesProvisionerLink < ApplicationRecord
  STATUSES = %w[linked unlinked].freeze

  belongs_to :account
  belongs_to :hermes_provisioner, class_name: 'JabvoxHermesProvisioner', inverse_of: :links

  validates :account_id, uniqueness: true
  validates :status_jabvox, inclusion: { in: STATUSES }

  scope :linked, -> { where(status_jabvox: 'linked') }

  # ¿Esta cuenta tiene el aprovisionador ligado y conectado?
  def self.active_for?(account_id)
    link = linked.find_by(account_id: account_id)
    link&.hermes_provisioner&.connected? || false
  end
end
