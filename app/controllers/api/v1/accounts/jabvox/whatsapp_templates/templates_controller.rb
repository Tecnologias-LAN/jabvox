class Api::V1::Accounts::Jabvox::WhatsappTemplates::TemplatesController < Api::V1::Accounts::Jabvox::WhatsappTemplates::BaseController
  before_action :set_template, only: [:show, :update, :destroy, :duplicate, :sync, :history, :versions, :restore_version]

  def index
    result = manager.list(
      filters: filter_params,
      page: params[:page] || 1,
      per_page: params[:per_page] || 50
    )
    render json: {
      templates: result[:templates].map { |t| serialize(t) },
      total: result[:total],
      page: result[:page],
      per_page: result[:per_page]
    }
  end

  def show
    render json: serialize(@template, full: true)
  end

  def create
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    result = manager.create(inbox, template_params)
    if result[:success]
      render json: serialize(result[:template], full: true), status: :created
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def update
    result = manager.update(@template, template_params)
    if result[:success]
      render json: serialize(result[:template], full: true)
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def destroy
    result = manager.destroy(@template)
    if result[:success]
      head :no_content
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def duplicate
    result = manager.duplicate(@template, new_name: params[:new_name])
    if result[:success]
      render json: serialize(result[:template], full: true), status: :created
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def sync
    result = manager.sync_single(@template)
    if result[:success]
      render json: serialize(result[:template], full: true)
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  def history
    logs = @template.logs.order(created_at: :desc).limit(50)
    render json: { history: logs.map { |l| serialize_log(l) } }
  end

  def versions
    render json: { versions: @template.versions.order(version: :desc).map { |v| serialize_version(v) } }
  end

  def restore_version
    result = manager.restore_version(@template, params.require(:version_id))
    if result[:success]
      render json: serialize(result[:template], full: true)
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  private

  def set_template
    @template = Current.account.jabvox_whatsapp_templates.find(params[:id])
  end

  def template_params
    params.permit(
      :name, :category, :language, :inbox_id,
      :header_type, :header_content, :body, :footer,
      buttons: [:type, :text, :url, :phone_number]
    ).to_h.symbolize_keys
  end

  def filter_params
    params.permit(:inbox_id, :status, :category, :language, :q, :date_from, :date_to).to_h.symbolize_keys
  end

  def serialize(tpl, full: false) # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
    base = {
      id: tpl.id,
      meta_template_id: tpl.meta_template_id,
      inbox_id: tpl.inbox_id,
      inbox_name: tpl.inbox&.name,
      waba_id: tpl.waba_id,
      phone_number_id: tpl.phone_number_id,
      name: tpl.name,
      language: tpl.language,
      category: tpl.category,
      status: tpl.status,
      quality_score: tpl.quality_score,
      rejected_reason: tpl.rejected_reason,
      header_type: tpl.header_type,
      header_content: tpl.header_content,
      body_content: tpl.body_content,
      footer_content: tpl.footer_content,
      buttons_json: tpl.buttons_json,
      variables_json: tpl.variables_json,
      created_by_name: tpl.created_by&.name,
      created_at: tpl.created_at,
      updated_at: tpl.updated_at
    }
    base[:meta_json] = tpl.meta_json if full
    base[:version_count] = tpl.versions.count if full
    base
  end

  def serialize_log(log)
    {
      id: log.id,
      action: log.action,
      description: log.description,
      user_name: log.user&.name || 'Sistema',
      created_at: log.created_at
    }
  end

  def serialize_version(ver)
    {
      id: ver.id,
      version: ver.version,
      payload: ver.payload,
      created_by_name: ver.created_by&.name,
      created_at: ver.created_at
    }
  end
end
