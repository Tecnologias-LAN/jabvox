class JabvoxResponseBotDocumentPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_response_bot_manage') || false
  end

  def index?   = can_manage?
  def sync?    = can_manage?
  def update?  = can_manage?
  def destroy? = can_manage?
end
