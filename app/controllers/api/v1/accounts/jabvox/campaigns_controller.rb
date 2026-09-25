class Api::V1::Accounts::Jabvox::CampaignsController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :ensure_module_permission
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

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_campaigns_manage')
  end

  def set_campaign
    @campaign = Current.account.jabvox_campaigns.find(params[:id])
  end

  def campaign_params
    params.require(:campaign).permit(:name_jabvox)
  end

end
