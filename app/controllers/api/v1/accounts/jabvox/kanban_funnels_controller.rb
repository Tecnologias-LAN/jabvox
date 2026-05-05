class Api::V1::Accounts::Jabvox::KanbanFunnelsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :fetch_funnel, only: [:show, :update, :destroy]
  before_action :check_authorization

  def index
    @funnels = policy_scope(Current.account.jabvox_kanban_funnels.ordered.includes(:jabvox_kanban_stages, :inboxes))
  end

  def show; end

  def create
    @funnel = Current.account.jabvox_kanban_funnels.new(funnel_params)
    @funnel.save!
    update_inbox_associations
    update_campaign_associations
    update_affiliate_associations
  end

  def update
    @funnel.update!(funnel_params)
    update_inbox_associations
    update_campaign_associations
    update_affiliate_associations
  end

  def destroy
    @funnel.destroy!
    head :ok
  end

  private

  def fetch_funnel
    @funnel = Current.account.jabvox_kanban_funnels.find(params[:id])
  end

  def check_authorization
    authorize @funnel || JabvoxKanbanFunnel
  end

  def funnel_params
    params.require(:funnel).permit(:name_jabvox, :description_jabvox, :position_jabvox, :active_jabvox)
  end

  def update_inbox_associations
    return unless params[:inbox_ids].is_a?(Array)

    inbox_ids = params[:inbox_ids].map(&:to_i)
    valid_inbox_ids = Current.account.inboxes.where(id: inbox_ids).pluck(:id)
    @funnel.jabvox_kanban_funnel_inboxes.where.not(inbox_id: valid_inbox_ids).destroy_all
    existing_ids = @funnel.jabvox_kanban_funnel_inboxes.pluck(:inbox_id)
    (valid_inbox_ids - existing_ids).each do |inbox_id|
      @funnel.jabvox_kanban_funnel_inboxes.create!(inbox_id: inbox_id)
    end
  end

  def update_campaign_associations
    return unless params[:campaign_ids].is_a?(Array)

    campaign_ids = params[:campaign_ids].map(&:to_i)
    valid_ids = Current.account.jabvox_campaigns.where(id: campaign_ids).pluck(:id)
    @funnel.jabvox_kanban_funnel_campaigns.where.not(jabvox_campaign_id: valid_ids).destroy_all
    existing_ids = @funnel.jabvox_kanban_funnel_campaigns.pluck(:jabvox_campaign_id)
    (valid_ids - existing_ids).each do |cid|
      @funnel.jabvox_kanban_funnel_campaigns.create!(jabvox_campaign_id: cid)
    end
  end

  def update_affiliate_associations
    return unless params[:affiliate_ids].is_a?(Array)

    affiliate_ids = params[:affiliate_ids].map(&:to_i)
    valid_ids = Current.account.jabvox_affiliates.where(id: affiliate_ids).pluck(:id)
    @funnel.jabvox_kanban_funnel_affiliates.where.not(jabvox_affiliate_id: valid_ids).destroy_all
    existing_ids = @funnel.jabvox_kanban_funnel_affiliates.pluck(:jabvox_affiliate_id)
    (valid_ids - existing_ids).each do |aid|
      @funnel.jabvox_kanban_funnel_affiliates.create!(jabvox_affiliate_id: aid)
    end
  end
end
