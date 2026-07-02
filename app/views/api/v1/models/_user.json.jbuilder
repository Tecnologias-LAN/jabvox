# Security: the API access token is only serialized when a super admin has
# explicitly enabled it for this user (can_view_access_token_jabvox). Disabled by
# default, so the token never leaves the backend — not even in the JSON payload —
# until it is turned on. This is the real gate; the profile UI is only cosmetic.
json.access_token resource.access_token.token if resource.can_view_access_token_jabvox?
json.can_view_access_token_jabvox resource.can_view_access_token_jabvox?
json.account_id resource.active_account_user&.account_id
json.available_name resource.available_name
json.avatar_url resource.avatar_url
json.confirmed resource.confirmed?
json.display_name resource.display_name
json.message_signature resource.message_signature
json.email resource.email
json.hmac_identifier resource.hmac_identifier if GlobalConfig.get('JABVOX_INBOX_HMAC_KEY')['JABVOX_INBOX_HMAC_KEY'].present?
json.id resource.id
json.inviter_id resource.active_account_user&.inviter_id
json.name resource.name
json.provider resource.provider
json.pubsub_token resource.pubsub_token
json.custom_attributes resource.custom_attributes if resource.custom_attributes.present?
json.role resource.active_account_user&.role
json.ui_settings resource.ui_settings
json.uid resource.uid
json.type resource.type
json.accounts do
  json.array! resource.account_users do |account_user|
    json.id account_user.account_id
    json.name account_user.account.name
    json.status account_user.account.status
    json.active_at account_user.active_at
    json.role account_user.role
    json.permissions account_user.permissions
    # the actual availability user has configured
    json.availability account_user.availability
    # availability derived from presence
    json.availability_status account_user.availability_status
    json.auto_offline account_user.auto_offline
    json.partial! 'api/v1/models/account_user', account_user: account_user if JabvoxApp.enterprise?
  end
end
