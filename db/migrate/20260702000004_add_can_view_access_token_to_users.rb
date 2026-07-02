class AddCanViewAccessTokenToUsers < ActiveRecord::Migration[7.1]
  # Whether this user may see their API access token in Profile Settings.
  # Disabled by default for both new and existing users (null: false + default
  # false), so the token is hidden until a super admin explicitly enables it.
  def change
    add_column :users, :can_view_access_token_jabvox, :boolean, default: false, null: false
  end
end
