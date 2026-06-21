class Api::V1::Accounts::Jabvox::Analytics::SharesController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  before_action :set_dashboard
  before_action :ensure_can_share!

  def index
    render json: @dashboard.shares.map { |s| serialize(s) }
  end

  def create
    share = @dashboard.shares.new(share_params)
    share.account = Current.account
    share.created_by = current_user
    if share.save
      audit!(action: 'share.create', auditable: @dashboard, metadata: share_params.to_h)
      render json: serialize(share), status: :created
    else
      render json: { errors: share.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    share = @dashboard.shares.find(params[:id])
    if share.update(share_params)
      render json: serialize(share)
    else
      render json: { errors: share.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    share = @dashboard.shares.find(params[:id])
    share.destroy!
    audit!(action: 'share.delete', auditable: @dashboard)
    head :no_content
  end

  private

  def set_dashboard
    @dashboard = Current.account.jabvox_analytics_dashboards.find(params[:dashboard_id])
  end

  def ensure_can_share!
    return if permission_resolver.can?(:share) &&
              Jabvox::Analytics::ShareService.new(@dashboard, current_user, Current.account).can_admin?

    render json: { error: 'No puedes administrar el acceso de este dashboard' }, status: :forbidden
  end

  def share_params
    params.require(:share).permit(:subject_type_jabvox, :subject_id_jabvox, :access_level_jabvox)
  end

  def serialize(share)
    {
      id: share.id,
      subject_type_jabvox: share.subject_type_jabvox,
      subject_id_jabvox: share.subject_id_jabvox,
      access_level_jabvox: share.access_level_jabvox
    }
  end
end
