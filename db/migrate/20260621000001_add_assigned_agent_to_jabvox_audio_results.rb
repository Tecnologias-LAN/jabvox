# frozen_string_literal: true

class AddAssignedAgentToJabvoxAudioResults < ActiveRecord::Migration[7.1]
  def change
    # The agent responsible for each analyzed audio (e.g. the advisor whose call
    # it is). Optional; set from the Analyzer when launching a job. Used to
    # filter reports by agent.
    add_reference :jabvox_audio_results, :assigned_agent,
                  foreign_key: { to_table: :users }, null: true, index: true
  end
end
