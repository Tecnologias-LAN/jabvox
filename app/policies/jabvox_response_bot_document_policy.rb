class JabvoxResponseBotDocumentPolicy < ApplicationPolicy
  def index?   = @account_user.administrator?
  def sync?    = @account_user.administrator?
  def update?  = @account_user.administrator?
  def destroy? = @account_user.administrator?
end
