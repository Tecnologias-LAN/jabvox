class JabvoxAiChatConfigPolicy < ApplicationPolicy
  # Admins always pass; a custom role granting jabvox_ai_chat_manage also passes.
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_ai_chat_manage') || false
  end

  def show? = can_manage?
  def update? = can_manage?
  def sync_documents? = can_manage?
end
