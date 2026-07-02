class JabvoxDialerCampaignPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_dialer_manage') || false
  end

  def index?        = @account_user.administrator? || @account_user.agent?
  def show?         = @account_user.administrator? || @account_user.agent?
  def create?       = can_manage?
  def update?       = can_manage?
  def destroy?      = can_manage?
  def lead_count?   = @account_user.administrator? || @account_user.agent?
  def start?        = can_manage?
  def pause?        = can_manage?
  def stop?         = can_manage?
  def contacts?     = @account_user.administrator? || @account_user.agent?
  def call_logs?    = @account_user.administrator? || @account_user.agent?
  def report?       = @account_user.administrator? || @account_user.agent?
  def import_contacts? = can_manage?
  def originate?    = @account_user.administrator? || @account_user.agent?

  class Scope < Scope
    def resolve = scope.all
  end
end
