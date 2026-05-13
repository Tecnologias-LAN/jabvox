json.id @config.id
json.from_name @config.from_name
json.from_email @config.from_email
json.address @config.address
json.port @config.port
json.domain @config.domain
json.username @config.username
json.has_password @config.password.present?
json.authentication @config.authentication
json.enable_starttls_auto @config.enable_starttls_auto
json.enable_ssl_tls @config.enable_ssl_tls
json.verified @config.verified
json.calendar_reminders_enabled @config.calendar_reminders_enabled
json.calendar_reminder_minutes @config.calendar_reminder_minutes || []
json.created_at @config.created_at
json.updated_at @config.updated_at
