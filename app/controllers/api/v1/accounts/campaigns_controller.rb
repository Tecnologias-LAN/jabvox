class Api::V1::Accounts::CampaignsController < Api::V1::Accounts::BaseController
  before_action :check_authorization

  def index
    @campaigns = Current.account.campaigns
  end
end
