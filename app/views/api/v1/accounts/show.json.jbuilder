json.partial! 'api/v1/models/account', formats: [:json], resource: @account
json.latest_jabvox_version @latest_jabvox_version
json.partial! 'enterprise/api/v1/accounts/partials/account', account: @account if JabvoxApp.enterprise?
