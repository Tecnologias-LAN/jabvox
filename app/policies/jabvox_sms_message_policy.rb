class JabvoxSmsMessagePolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_sms_view') || false
  end

  def index? = can_manage?
  def stats? = can_manage?
end
