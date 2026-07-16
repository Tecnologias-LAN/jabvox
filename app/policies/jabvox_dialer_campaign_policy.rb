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
  # Exposes lead PII (phone/email/document) for building the campaign list:
  # restricted to users who can manage campaigns.
  def preview_leads? = can_manage?
  def matching_lead_ids? = can_manage?
  # Field definitions only (no lead data), needed by the campaign form.
  def lead_fields?  = can_manage?
  def start?        = can_manage?
  def pause?        = can_manage?
  def stop?         = can_manage?
  def contacts?     = @account_user.administrator? || @account_user.agent?
  def call_logs?    = @account_user.administrator? || @account_user.agent?
  def report?       = @account_user.administrator? || @account_user.agent?
  def import_contacts? = can_manage?
  def originate?    = @account_user.administrator? || @account_user.agent?
  def retry_contacts? = can_manage?
  def progress?     = @account_user.administrator? || @account_user.agent?
  def redial_lead?  = can_manage?
  def exclude_lead? = can_manage?

  class Scope < Scope
    def resolve = scope.all
  end
end
