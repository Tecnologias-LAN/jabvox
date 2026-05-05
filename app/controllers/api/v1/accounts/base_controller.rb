class Api::V1::Accounts::BaseController < Api::BaseController
  include SwitchLocale
  include EnsureCurrentAccountHelper
  include JabvoxIpWhitelistCheck
  include JabvoxFieldMasker
  before_action :current_account
  before_action :check_jabvox_ip_whitelist
  around_action :switch_locale_using_account_locale
end
