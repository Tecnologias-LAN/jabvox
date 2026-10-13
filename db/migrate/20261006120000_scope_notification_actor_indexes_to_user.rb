class ScopeNotificationActorIndexesToUser < ActiveRecord::Migration[7.1]
  def change
    remove_index :notifications,
                 column: %i[primary_actor_type primary_actor_id],
                 name: :uniq_primary_actor_per_account_notifications
    remove_index :notifications,
                 column: %i[secondary_actor_type secondary_actor_id],
                 name: :uniq_secondary_actor_per_account_notifications

    add_index :notifications, %i[account_id user_id primary_actor_type primary_actor_id],
              unique: true, name: :uniq_notification_primary_actor_per_user
    add_index :notifications, %i[account_id user_id secondary_actor_type secondary_actor_id],
              unique: true, name: :uniq_notification_secondary_actor_per_user
  end
end
