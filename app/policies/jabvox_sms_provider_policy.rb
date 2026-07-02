class JabvoxSmsProviderPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_sms_manage') || false
  end

  def index? = can_manage?
  def show? = can_manage?
  def create? = can_manage?
  def update? = can_manage?
  def destroy? = can_manage?
  def check_connection? = can_manage?
end
