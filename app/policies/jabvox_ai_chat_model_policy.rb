class JabvoxAiChatModelPolicy < ApplicationPolicy
  def index?    = @account_user.administrator?
  def create?   = @account_user.administrator?
  def update?   = @account_user.administrator?
  def destroy?  = @account_user.administrator?
  def set_default? = @account_user.administrator?
  def test_connection? = @account_user.administrator?
end
