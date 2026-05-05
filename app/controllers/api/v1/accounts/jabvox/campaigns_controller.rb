class Api::V1::Accounts::Jabvox::CampaignsController < Api::V1::Accounts::BaseController
  before_action :check_leads_enabled
  before_action :set_campaign, only: [:update, :destroy]

  def index
    @campaigns = Current.account.jabvox_campaigns.ordered
  end

  def create
    @campaign = Current.account.jabvox_campaigns.create!(campaign_params)
    render json: { id: @campaign.id, name: @campaign.name_jabvox }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @campaign.update!(campaign_params)
    render json: { id: @campaign.id, name: @campaign.name_jabvox }
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @campaign.destroy!
    head :no_content
  end

  private

  def set_campaign
    @campaign = Current.account.jabvox_campaigns.find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:name_jabvox)
  end

  def check_leads_enabled
    render json: { error: 'Leads module not enabled' }, status: :forbidden unless Current.account.jabvox_leads_enabled_jabvox?
  end
end
