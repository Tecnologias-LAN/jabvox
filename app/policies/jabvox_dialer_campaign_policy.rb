class JabvoxDialerCampaignPolicy < ApplicationPolicy
  def index?        = @account_user.administrator? || @account_user.agent?
  def show?         = @account_user.administrator? || @account_user.agent?
  def create?       = @account_user.administrator?
  def update?       = @account_user.administrator?
  def destroy?      = @account_user.administrator?
  def lead_count?   = @account_user.administrator? || @account_user.agent?
  def start?        = @account_user.administrator?
  def pause?        = @account_user.administrator?
  def stop?         = @account_user.administrator?
  def contacts?     = @account_user.administrator? || @account_user.agent?
  def call_logs?    = @account_user.administrator? || @account_user.agent?
  def report?       = @account_user.administrator? || @account_user.agent?
  def import_contacts? = @account_user.administrator?
  def originate?    = @account_user.administrator? || @account_user.agent?

  class Scope < Scope
    def resolve = scope.all
  end
end
