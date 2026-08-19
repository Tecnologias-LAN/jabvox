# frozen_string_literal: true

# Mensaje del "Chat Aprovisionamiento" de una cuenta: la conversación entre un usuario
# (con permiso) y el Hermes Provisioner de esa cuenta, donde se le pide crear MCPs
# (analytics, reportes, etc.) o aprovisionar por primera vez su Hermes/ContextForge.
#
# Guarda quién pidió cada cosa (user_id) para auditoría y para gating por permisos.
#
# == Schema Information
#
# Table name: jabvox_provisioning_chat_messages
#
#  id         :bigint           not null, primary key
#  content    :text
#  metadata   :jsonb            not null
#  role       :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint           not null
#  user_id    :bigint           not null
#
class JabvoxProvisioningChatMessage < ApplicationRecord
  belongs_to :account
  belongs_to :user

  ROLES = %w[user assistant system].freeze

  validates :role, inclusion: { in: ROLES }

  scope :recent_first, -> { order(created_at: :desc) }
  scope :chronological, -> { order(created_at: :asc) }
end
