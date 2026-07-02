class JabvoxAiChatModelPolicy < ApplicationPolicy
  # Admins always pass; a custom role granting jabvox_ai_chat_manage also passes.
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_ai_chat_manage') || false
  end

  def index?    = can_manage?
  def create?   = can_manage?
  def update?   = can_manage?
  def destroy?  = can_manage?
  def set_default? = can_manage?
  def test_connection? = can_manage?
end
