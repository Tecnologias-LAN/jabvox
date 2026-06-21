json.feature_available Jabvox.mfa_enabled?
json.enabled @user.mfa_enabled?
json.backup_codes_generated @user.mfa_service.backup_codes_generated? if Jabvox.mfa_enabled?
