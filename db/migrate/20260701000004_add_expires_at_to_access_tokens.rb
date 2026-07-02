class AddExpiresAtToAccessTokens < ActiveRecord::Migration[7.1]
  def change
    # Nullable on purpose: existing/regular tokens never expire (expires_at IS NULL).
    # Only short-lived tokens (e.g. the 30-minute Bulk WhatsApp token) set a value, and
    # authentication rejects them once expires_at has passed.
    add_column :access_tokens, :expires_at, :datetime
    add_index :access_tokens, :expires_at
  end
end
