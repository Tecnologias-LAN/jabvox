class JabvoxSmsCampaignPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_sms_manage') || false
  end

  def index? = can_manage?
  def show? = can_manage?
  def create? = can_manage?
  def update? = can_manage?
  def destroy? = can_manage?
  def send_bulk? = can_manage?
  def contacts? = can_manage?
  def lead_count? = can_manage?
end
