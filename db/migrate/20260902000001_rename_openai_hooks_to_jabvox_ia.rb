# frozen_string_literal: true

# The OpenAI integration was rebranded to "Jabvox IA" and its integration id
# changed from 'openai' to 'jabvox_ia'. Existing connections are stored as
# integrations_hooks with app_id='openai'; rename them so they keep working
# under the new id (otherwise they'd be orphaned and the account would look
# disconnected). Data-only, reversible.
class RenameOpenaiHooksToJabvoxIa < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    execute("UPDATE integrations_hooks SET app_id = 'jabvox_ia' WHERE app_id = 'openai'")
  end

  def down
    execute("UPDATE integrations_hooks SET app_id = 'openai' WHERE app_id = 'jabvox_ia'")
  end
end
