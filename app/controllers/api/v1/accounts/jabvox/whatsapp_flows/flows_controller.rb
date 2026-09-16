class Api::V1::Accounts::Jabvox::WhatsappFlows::FlowsController < Api::V1::Accounts::Jabvox::WhatsappFlows::BaseController
  before_action :set_flow, only: [:show, :update, :destroy, :validate, :publish, :sync, :duplicate, :versions, :submissions, :metrics]

  def index
    scope = Current.account.jabvox_whatsapp_flows.includes(:inbox, :created_by)
    scope = scope.by_inbox(params[:inbox_id])
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.by_category(params[:category])
    scope = scope.search_text(params[:q])
    total = scope.count
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    records = scope.order(created_at: :desc).offset((page - 1) * per_page).limit(per_page)

    render json: { flows: records.map { |f| serialize(f) }, total: total, page: page, per_page: per_page }
  end

  def show
    render json: serialize(@flow, full: true)
  end

  def create
    inbox = Current.account.inboxes.find(flow_params[:inbox_id])
    channel = inbox.channel
    flow = Current.account.jabvox_whatsapp_flows.create!(
      inbox: inbox,
      waba_id: channel.provider_config['business_account_id'],
      name: flow_params[:name],
      category: flow_params[:category],
      description: flow_params[:description],
      screens_json: flow_params[:screens_json] || [],
      created_by: Current.user
    )
    render json: serialize(flow, full: true), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    return render json: { error: 'No se puede editar un Flow publicado en Meta' }, status: :unprocessable_entity if @flow.published_on_meta?

    @flow.update!(update_params)
    render json: serialize(@flow, full: true)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    if @flow.meta_flow_id.present?
      return render json: { error: 'No se puede eliminar un Flow ya sincronizado con Meta' }, status: :unprocessable_entity
    end

    @flow.destroy!
    head :no_content
  end

  def validate
    result = Jabvox::WhatsappFlows::Validator.new(@flow).call
    @flow.update!(validation_errors_json: result[:errors])
    render json: result
  end

  def publish
    result = Jabvox::WhatsappFlows::PublishService.new(@flow, user: Current.user).call(publish: params[:publish].to_s == 'true')
    if result[:success]
      render json: serialize(@flow, full: true)
    else
      render json: { error: result[:error], errors: result[:errors] }, status: :unprocessable_entity
    end
  end

  def sync
    client = Jabvox::WhatsappFlows::MetaClient.new(@flow)
    result = client.fetch_status
    if result[:success]
      data = result[:data]
      @flow.update!(meta_status: data['status'], meta_json: data, validation_errors_json: data['validation_errors'] || [])
      render json: serialize(@flow, full: true)
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  # Creates a fresh, editable draft copy — the only way to change a PUBLISHED Flow's
  # screens (architecture doc section 6). Never carries over meta_flow_id/meta_status
  # so the duplicate becomes its own separate Flow in Meta once published.
  def duplicate
    dup = Current.account.jabvox_whatsapp_flows.create!(
      inbox: @flow.inbox,
      waba_id: @flow.waba_id,
      name: params[:new_name].presence || "#{@flow.name}_copy",
      category: @flow.category,
      description: @flow.description,
      status: 'draft',
      screens_json: @flow.screens_json,
      created_by: Current.user
    )
    render json: serialize(dup, full: true), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def versions
    render json: { versions: @flow.versions.order(version: :desc).map { |v| serialize_version(v) } }
  end

  def submissions
    scope = @flow.submissions.includes(:contact).recent_first
    total = scope.count
    page = (params[:page] || 1).to_i
    per_page = (params[:per_page] || 50).to_i
    records = scope.offset((page - 1) * per_page).limit(per_page)

    render json: {
      submissions: records.map { |s| serialize_submission(s) },
      total: total, page: page, per_page: per_page
    }
  end

  def metrics
    submissions = @flow.submissions
    render json: {
      total_submissions: submissions.count,
      last_submission_at: submissions.maximum(:completed_at),
      status: @flow.status,
      meta_status: @flow.meta_status
    }
  end

  def categories
    render json: { categories: JabvoxWhatsappFlow::CATEGORIES }
  end

  private

  def set_flow
    @flow = Current.account.jabvox_whatsapp_flows.find(params[:id])
  end

  def flow_params
    params.permit(:inbox_id, :name, :category, :description, screens_json: {}).to_h.symbolize_keys
  end

  def update_params
    params.permit(:name, :category, :description, screens_json: {}).to_h.symbolize_keys.compact
  end

  def serialize(flow, full: false) # rubocop:disable Metrics/MethodLength
    base = {
      id: flow.id,
      inbox_id: flow.inbox_id,
      inbox_name: flow.inbox&.name,
      waba_id: flow.waba_id,
      name: flow.name,
      category: flow.category,
      description: flow.description,
      status: flow.status,
      meta_flow_id: flow.meta_flow_id,
      meta_status: flow.meta_status,
      published_at: flow.published_at,
      created_by_name: flow.created_by&.name,
      created_at: flow.created_at,
      updated_at: flow.updated_at
    }
    if full
      base[:screens_json] = flow.screens_json
      base[:validation_errors_json] = flow.validation_errors_json
      base[:meta_json] = flow.meta_json
      base[:version_count] = flow.versions.count
    end
    base
  end

  def serialize_version(version)
    {
      id: version.id,
      version: version.version,
      screens_json: version.screens_json,
      created_by_name: version.created_by&.name,
      created_at: version.created_at
    }
  end

  def serialize_submission(submission)
    {
      id: submission.id,
      contact_id: submission.contact_id,
      contact_name: submission.contact&.name,
      conversation_id: submission.conversation_id,
      flow_token: submission.flow_token,
      status: submission.status,
      completed_at: submission.completed_at,
      answers: submission.answers.map { |a| { component_name: a.component_name, value_text: a.value_text } }
    }
  end
end
