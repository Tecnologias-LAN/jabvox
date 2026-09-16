# Crea, en un solo paso para el usuario, una plantilla cuyo botón abre un
# WhatsApp Flow recién construido en el mismo formulario.
#
# Meta obliga a que sean dos objetos separados y en este orden: el Flow debe
# existir y estar PUBLICADO antes de que una plantilla pueda referenciarlo por
# su id. Este servicio encadena esos pasos para que el wizard no tenga que
# exponer esa secuencia:
#
#   1. Crea el JabvoxWhatsappFlow con las pantallas del formulario.
#   2. Lo valida y lo publica en Meta (PublishService).
#   3. Crea la plantilla con un botón FLOW apuntando al meta_flow_id resultante.
#
# Si algo falla, no deja una plantilla a medias: devuelve el error y (cuando el
# Flow ya se había creado localmente sin publicarse) lo deja como borrador para
# que el usuario pueda retomarlo desde el módulo de Flows.
class Jabvox::WhatsappTemplates::FlowTemplateCreator
  def initialize(account, user: nil)
    @account = account
    @user = user
  end

  # params: los mismos del creador de plantillas, más:
  #   flow: { name:, category:, screens_json: [...] }
  #   flow_button_text: texto del botón que abre el Flow
  def call(inbox, params)
    flow_params = (params[:flow] || {}).to_h.symbolize_keys
    return { success: false, error: 'Falta la definición del formulario (flow).' } if flow_params[:screens_json].blank?

    flow = build_flow(inbox, flow_params, params)
    return { success: false, error: flow.errors.full_messages.to_sentence } unless flow.persisted?

    publish = Jabvox::WhatsappFlows::PublishService.new(flow, user: @user).call(publish: true)
    return publish_failure(publish) unless publish[:success]

    create_template(inbox, params, flow.reload)
  end

  private

  def build_flow(inbox, flow_params, params)
    @account.jabvox_whatsapp_flows.create(
      inbox: inbox,
      waba_id: inbox.channel.provider_config['business_account_id'],
      # Sin nombre propio, el Flow hereda el de la plantilla: son una sola cosa
      # desde el punto de vista del usuario.
      name: flow_params[:name].presence || params[:name],
      category: flow_params[:category].presence || 'OTHER',
      description: flow_params[:description],
      screens_json: flow_params[:screens_json],
      status: 'draft',
      created_by: @user
    )
  end

  # El Flow queda guardado como borrador aunque falle la publicación, así el
  # usuario no pierde lo que construyó y puede corregirlo desde Flows.
  def publish_failure(result)
    { success: false,
      error: "No se pudo publicar el formulario en Meta: #{result[:error]}. " \
             'Quedó guardado como borrador en WhatsApp Flows.',
      errors: result[:errors] }
  end

  def create_template(inbox, params, flow)
    template_params = params.except(:flow, :flow_button_text).merge(
      template_kind: 'flow',
      buttons: [flow_button(params, flow)]
    )

    result = Jabvox::WhatsappTemplatesManager.new(@account, user: @user).create(inbox, template_params)
    return result unless result[:success]

    result[:template].update(jabvox_whatsapp_flow_id: flow.id)
    result.merge(flow: flow)
  end

  def flow_button(params, flow)
    {
      type: 'FLOW',
      text: params[:flow_button_text].presence || 'Comenzar',
      flow_id: flow.meta_flow_id,
      navigate_screen: first_screen_id(flow)
    }
  end

  def first_screen_id(flow)
    Array(flow.screens_json).min_by { |s| s['order'].to_i }&.dig('id')
  end
end
