# Auditoría de cada acción ejecutada por una tool de Hermes. Se escribe en el BACKEND al
# momento de autorizar/ejecutar (no lo reporta Hermes, que no es de fiar). Nunca guarda
# secretos ni tokens — solo params relevantes ya saneados.
# == Schema Information
#
# Table name: jabvox_hermes_action_logs
#
#  id                     :bigint           not null, primary key
#  duration_ms_jabvox     :integer
#  error_jabvox           :text
#  hermes_identity_jabvox :string
#  params_jabvox          :jsonb
#  permission_jabvox      :string
#  status_jabvox          :string           not null
#  tool_jabvox            :string           not null
#  created_at             :datetime         not null
#  account_id             :bigint           not null
#  user_id                :bigint
#
# Indexes
#
#  index_jabvox_hermes_action_logs_on_account_id                  (account_id)
#  index_jabvox_hermes_action_logs_on_account_id_and_created_at   (account_id,created_at)
#  index_jabvox_hermes_action_logs_on_account_id_and_tool_jabvox  (account_id,tool_jabvox)
#  index_jabvox_hermes_action_logs_on_user_id                     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxHermesActionLog < ApplicationRecord
  STATUSES = %w[success forbidden error].freeze

  belongs_to :account
  belongs_to :user, optional: true

  validates :tool_jabvox, :status_jabvox, presence: true

  # Registra una acción. `entry` es un hash con: account_id, user_id, hermes_identity, tool,
  # permission, status, params, error, duration_ms. Nunca revienta el flujo principal.
  def self.record!(entry = {})
    e = entry
    create!(
      account_id: e[:account_id], user_id: e[:user_id],
      hermes_identity_jabvox: e[:hermes_identity], tool_jabvox: e[:tool],
      permission_jabvox: e[:permission], status_jabvox: e[:status],
      params_jabvox: sanitize(e[:params] || {}), error_jabvox: e[:error].to_s.first(1000),
      duration_ms_jabvox: e[:duration_ms], created_at: Time.current
    )
  rescue StandardError => e
    Rails.logger.error("[HermesActionLog] no se pudo auditar: #{e.class}: #{e.message}")
    nil
  end

  # Quita cualquier clave que huela a secreto antes de persistir los params.
  def self.sanitize(params)
    return {} unless params.is_a?(Hash)

    params.reject { |k, _| k.to_s.match?(/token|password|secret|api_key|authorization/i) }
  end
end
