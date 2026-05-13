json.base_url_jabvox @config.base_url_jabvox || ''
json.max_forms_jabvox @config.max_forms_jabvox || 10
json.ssl_status       @config.ssl_status
json.ssl_expires_at   @config.ssl_expires_at&.iso8601
json.ssl_provisioned_at @config.ssl_provisioned_at&.iso8601
json.ssl_error        @config.ssl_error
