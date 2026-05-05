class JabvoxAiChatPermissionPolicy < ApplicationPolicy
  def index?       = @account_user.administrator?
  def bulk_update? = @account_user.administrator?
  def update?      = @account_user.administrator?
end
