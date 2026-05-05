class JabvoxSmsCampaignPolicy < ApplicationPolicy
  def index? = @account_user.administrator?
  def show? = @account_user.administrator?
  def create? = @account_user.administrator?
  def update? = @account_user.administrator?
  def destroy? = @account_user.administrator?
  def send_bulk? = @account_user.administrator?
  def contacts? = @account_user.administrator?
  def lead_count? = @account_user.administrator?
end
