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
#  kind_jabvox         :string           not null, default("account")
#  session_id_jabvox   :string
#  last_used_at_jabvox :datetime
#  account_id          :bigint           not null
#  user_id             :bigint           not null
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
