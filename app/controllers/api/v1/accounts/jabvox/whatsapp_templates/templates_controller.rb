class Api::V1::Accounts::Jabvox::WhatsappTemplates::TemplatesController < Api::V1::Accounts::Jabvox::WhatsappTemplates::BaseController
  before_action :set_template, only: [:show, :update, :duplicate, :sync, :history, :versions, :restore_version]

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
    result = create_result(inbox)
    if result[:success]
      render json: serialize(result[:template], full: true), status: :created
    else
      render json: { error: result[:error], errors: result[:errors] }, status: :unprocessable_entity
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

  # Sube un archivo de media (imagen/video/documento) a Meta con la Resumable Upload
  # API y devuelve el handle "h:..." para usar como ejemplo del header al crear la
  # plantilla. Se llama ANTES de create, desde el editor cuando se elige un archivo.
  def upload_media
    inbox = Current.account.inboxes.find(params.require(:inbox_id))
    file = params.require(:file)
    result = manager.upload_media(
      inbox,
      file_path: file.tempfile.path,
      file_type: file.content_type,
      file_size: file.tempfile.size
    )
    if result[:success]
      render json: { handle: result[:handle] }
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

  # Una plantilla de tipo 'flow' crea además el Flow y lo publica en Meta antes
  # de referenciarlo, así que pasa por su propio orquestador.
  def create_result(inbox)
    return manager.create(inbox, template_params) unless template_params[:template_kind].to_s == 'flow'

    Jabvox::WhatsappTemplates::FlowTemplateCreator
      .new(Current.account, user: Current.user)
      .call(inbox, template_params)
  end

  def template_params
    params.permit(
      :name, :category, :language, :inbox_id,
      :header_type, :header_content, :header_handle, :body, :footer,
      :template_kind, :location_header, :limited_time_offer, :lto_text,
      # Ejemplo por variable ({ "nombre" => "Ana" }): Meta lo usa para revisar
      # la plantilla, así que conviene que sea realista y no genérico.
      { var_descriptions: {} },
      buttons: [:type, :text, :url, :phone_number, :flow_id, :navigate_screen, :example],
      cards: [
        :header_type, :header_handle, :body_content,
        { buttons: [:type, :text, :url, :phone_number] }
      ],
      auth_config: [
        :add_security_recommendation, :code_expiration_minutes, :otp_type,
        { supported_apps: [:package_name, :signature_hash] }
      ]
    ).to_h.symbolize_keys.merge(flow_params)
  end

  # Definición del Flow cuando la plantilla se crea con su formulario en el
  # mismo paso. screens_json es una estructura libre (pantallas > componentes >
  # props), así que se permite entera en vez de enumerar cada campo.
  def flow_params
    return {} if params[:flow].blank?

    {
      flow: params[:flow].permit!.to_h.symbolize_keys,
      flow_button_text: params[:flow_button_text]
    }.compact
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
      template_kind: tpl.template_kind,
      cards_json: tpl.cards_json,
      auth_config_json: tpl.auth_config_json,
      location_header: tpl.location_header,
      limited_time_offer: tpl.limited_time_offer,
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
