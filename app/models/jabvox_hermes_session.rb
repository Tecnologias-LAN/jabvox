# frozen_string_literal: true

# Sesión de Hermes por (cuenta + usuario + tipo). Reutiliza el session_id de la Sessions API
# de Hermes para mantener conversación continua (como Telegram mapea chat_id → sesión).
# 'account' = Chat IA de la cuenta; 'provisioner' = Chat Aprovisionador.
#
# == Schema Information
#
# Table name: jabvox_hermes_sessions
#
#  id                  :bigint           not null, primary key
#  kind_jabvox         :string           default("account"), not null
#  last_used_at_jabvox :datetime
#  session_id_jabvox   :string
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  user_id             :bigint           not null
#
# Indexes
#
#  idx_hermes_sessions_account_user_kind       (account_id,user_id,kind_jabvox) UNIQUE
#  index_jabvox_hermes_sessions_on_account_id  (account_id)
#  index_jabvox_hermes_sessions_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxHermesSession < ApplicationRecord
  KINDS = %w[account provisioner].freeze

  belongs_to :account
  belongs_to :user

  validates :kind_jabvox, inclusion: { in: KINDS }
  validates :account_id, uniqueness: { scope: %i[user_id kind_jabvox] }

  # Devuelve (creando si hace falta) la sesión de un (cuenta, usuario, tipo).
  def self.for(account_id:, user_id:, kind: 'account')
    find_or_create_by!(account_id: account_id, user_id: user_id, kind_jabvox: kind)
  end

  def remember!(session_id)
    update!(session_id_jabvox: session_id, last_used_at_jabvox: Time.current)
  end

  # Resetea la sesión (para /new o cuando Hermes ya no la reconoce).
  def reset!
    update!(session_id_jabvox: nil)
  end
end
