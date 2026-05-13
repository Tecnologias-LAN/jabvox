class JabvoxFormPolicy < ApplicationPolicy
  def index?   = @account_user.administrator?
  def show?    = @account_user.administrator?
  def create?  = @account_user.administrator?
  def update?  = @account_user.administrator?
  def destroy? = @account_user.administrator?
end
