# == Schema Information
#
# Table name: jabvox_ai_chat_sessions
#
#  id                :bigint           not null, primary key
#  session_id_jabvox :string(100)      not null
#  title_jabvox      :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :bigint           not null
#  connection_id     :bigint
#  user_id           :bigint
#
# Indexes
#
#  idx_jabvox_ai_chat_sessions_uniq             (account_id,user_id,session_id_jabvox) UNIQUE
#  index_jabvox_ai_chat_sessions_on_account_id  (account_id)
#  index_jabvox_ai_chat_sessions_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
# Sesión del Chat IA. Da identidad (título renombrable + conexión/agente) a lo que antes era
# una sesión "virtual" (filas de jabvox_ai_chat_messages con el mismo session_id_jabvox).
# El historial del Chat IA es PRIVADO POR USUARIO: la sesión se identifica por
# (account_id, user_id, session_id_jabvox); cada usuario ve/renombra/borra solo las suyas.
class JabvoxAiChatSession < ApplicationRecord
  # Longitud del auto-título a partir del primer mensaje del usuario.
  AUTO_TITLE_LENGTH = 50

  belongs_to :account
  belongs_to :user

  validates :session_id_jabvox, presence: true, length: { maximum: 100 }
  validates :title_jabvox, length: { maximum: 255 }, allow_nil: true

  scope :for_account, ->(account_id) { where(account_id: account_id) }

  # Título a partir de las primeras ~50 chars del primer mensaje del usuario. Limpio de
  # saltos de línea y recortado; vacío → nil (el front cae a "Sesión N").
  def self.auto_title_from(text)
    cleaned = text.to_s.gsub(/\s+/, ' ').strip
    return nil if cleaned.empty?

    cleaned.length > AUTO_TITLE_LENGTH ? "#{cleaned[0, AUTO_TITLE_LENGTH].rstrip}…" : cleaned
  end
end
