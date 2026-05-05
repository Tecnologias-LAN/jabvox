class JabvoxAiChatConfigPolicy < ApplicationPolicy
  def show?   = @account_user.administrator?
  def update? = @account_user.administrator?
  def sync_documents? = @account_user.administrator?
end
