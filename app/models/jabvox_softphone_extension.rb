# frozen_string_literal: true

# Credencial SIP del usuario para registrar el softphone WebRTC. La EXTENSIÓN en sí sale
# del VoIP (jabvox_user_extensions); aquí solo se guarda el SECRETO de registro (cifrado),
# ligado por user+account, porque VoIP no maneja credenciales WebRTC.
#
# El sip_secret nunca se expone tal cual al navegador salvo dentro de la respuesta
# autenticada de credenciales (sobre HTTPS + WSS).
#
# == Schema
#   account_id, user_id (único por cuenta), sip_secret (cifrado), webrtc_enabled
# == Schema Information
#
# Table name: jabvox_softphone_extensions
#
#  id              :bigint           not null, primary key
#  last_error      :string
#  last_seen_at    :datetime
#  live_state      :string           default("disconnected"), not null
#  remote_ip       :string
#  sip_secret      :text
#  user_agent_info :string
#  webrtc_enabled  :boolean          default(TRUE), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  user_id         :bigint           not null
#
# Indexes
#
#  index_jabvox_softphone_extensions_on_account_id              (account_id)
#  index_jabvox_softphone_extensions_on_account_id_and_user_id  (account_id,user_id) UNIQUE
#  index_jabvox_softphone_extensions_on_last_seen_at            (last_seen_at)
#  index_jabvox_softphone_extensions_on_user_id                 (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxSoftphoneExtension < ApplicationRecord
  belongs_to :account
  belongs_to :user

  encrypts :sip_secret if Jabvox.encryption_configured?

  validates :user_id, uniqueness: { scope: :account_id }
  validates :sip_secret, presence: true

  scope :active, -> { where(webrtc_enabled: true) }

  # Credencial SIP del usuario en la cuenta (o nil).
  def self.for(account_id:, user_id:)
    active.find_by(account_id: account_id, user_id: user_id)
  end
end
