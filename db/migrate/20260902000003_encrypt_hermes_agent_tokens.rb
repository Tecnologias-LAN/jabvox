# frozen_string_literal: true

# agent_token_jabvox now uses ActiveRecord::Encryption (deterministic, so
# authenticate can still find_by the token). Existing rows are plaintext; re-save
# them once to store the encrypted form. support_unencrypted_data lets both the
# old and new rows be read during rollout.
class EncryptHermesAgentTokens < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    return unless Jabvox.encryption_configured?

    JabvoxHermesAgent.find_each do |agent|
      agent.update_column(:agent_token_jabvox, agent.agent_token_jabvox) # rubocop:disable Rails/SkipsModelValidations
    rescue StandardError => e
      Rails.logger.warn("[encrypt-hermes-token] agent ##{agent.id}: #{e.class} #{e.message}")
    end
  end

  def down; end
end
