# frozen_string_literal: true

# OPCIONES DINÁMICAS de los params del catálogo (`optionsSource`). Dentro del
# monolito se consultan los modelos directamente: no hay integración HTTP que
# configurar ni credenciales que resolver.
#
# Toda consulta se acota a la cuenta recibida: el editor de una cuenta nunca
# puede listar bandejas, plantillas ni productos de otra.
class Jabvox::Flows::OptionsService
  include Jabvox::Flows::LeadFieldOptions

  # Kinds servidos. Un kind fuera de esta lista es un 400, no una lista vacía:
  # un select vacío por una errata es indistinguible de "no hay datos".
  KINDS = %w[
    inboxes agents teams labels email_templates whatsapp_inboxes whatsapp_templates
    kanban_funnels kanban_stages task_boards task_stages typifications campaigns
    lead_custom_fields lead_field_keys lead_filter_fields contact_custom_attrs
    management_states sms_providers calendar_external_people products order_statuses
    analytics_data_sources companies
  ].freeze

  class UnknownKind < StandardError; end
  class MissingDependency < StandardError; end

  def initialize(account)
    @account = account
  end

  def call(kind, params = {})
    raise UnknownKind, "Kind de opciones desconocido: '#{kind}'." unless KINDS.include?(kind.to_s)

    public_send(:"opt_#{kind}", params.to_h.symbolize_keys)
  end

  # --------------------------- Chatwoot base ---------------------------------

  def opt_inboxes(_params)
    @account.inboxes.order(:name).map do |inbox|
      option(inbox.id, inbox.name, 'channel_type' => inbox.channel_type)
    end
  end

  def opt_agents(_params)
    @account.users.order(:name).map do |user|
      option(user.id, user.name.presence || user.email, 'email' => user.email)
    end
  end

  def opt_teams(_params)
    @account.teams.order(:name).map { |team| option(team.id, team.name) }
  end

  # Empresas (entidad) de la cuenta, para ligar el contacto desde un flujo. Vacío si
  # el módulo de empresas no está activo (la asociación vive en enterprise).
  def opt_companies(_params)
    return [] unless @account.feature_enabled?('companies')

    @account.companies.order(:name).map do |company|
      option(company.id, company.name, 'nit' => company.additional_attributes&.dig('nit'))
    end
  end

  # Las etiquetas se aplican por TÍTULO, por eso el valor es el título y no el id.
  def opt_labels(_params)
    @account.labels.order(:title).map do |label|
      option(label.title, label.title, 'id' => label.id, 'color' => label.color)
    end
  end

  def opt_contact_custom_attrs(_params)
    @account.custom_attribute_definitions.where(attribute_model: :contact_attribute)
            .order(:attribute_display_name).map do |attr|
      option(attr.attribute_key, attr.attribute_display_name.presence || attr.attribute_key,
             'type' => attr.attribute_display_type, 'options' => attr.attribute_values)
    end
  end

  # ----------------------------- Jabvox --------------------------------------

  def opt_email_templates(_params)
    JabvoxEmailTemplate.where(account_id: @account.id).order(:name).map do |tpl|
      option(tpl.id, tpl.name, 'subject' => tpl.subject, 'active' => tpl.active)
    end
  end

  def opt_whatsapp_inboxes(_params)
    JabvoxWhatsappTemplate.where(account_id: @account.id).distinct.pluck(:inbox_id).compact
                          .then { |ids| @account.inboxes.where(id: ids).order(:name) }
                          .map { |inbox| option(inbox.id, inbox.name) }
  end

  # El VALOR es el NOMBRE de la plantilla (es lo que viaja al enviar), no el id.
  # `meta` lleva la estructura completa (huecos, cabecera, botones) que el panel
  # necesita para pedir exactamente lo que el envío exige.
  def opt_whatsapp_templates(params)
    scope = JabvoxWhatsappTemplate.where(account_id: @account.id)
    scope = scope.where(inbox_id: params[:inboxId]) if params[:inboxId].present?
    templates = scope.where(status: [nil, '', 'APPROVED', 'approved']).order(:name)
    languages = languages_by_name(templates)

    templates.map do |tpl|
      structure = Jabvox::Flows::Nodes::WhatsappTemplateStructure.parse(tpl)
      option(structure['name'], "#{structure['name']} (#{structure['language']})",
             structure.merge('id' => tpl.id, 'inboxId' => tpl.inbox_id,
                             'languages' => languages[tpl.name] || []))
    end
  end

  def opt_kanban_funnels(_params)
    JabvoxKanbanFunnel.where(account_id: @account.id).order(:position_jabvox, :name_jabvox)
                      .map { |f| option(f.id, f.name_jabvox, 'active' => f.active_jabvox) }
  end

  def opt_kanban_stages(params)
    funnel_id = require_dependency!(params[:funnelId], 'kanban_stages', 'funnelId')
    JabvoxKanbanStage.where(account_id: @account.id, jabvox_kanban_funnel_id: funnel_id)
                     .order(:position_jabvox).map do |stage|
      option(stage.id, stage.name_jabvox, 'color' => stage.color_jabvox,
                                          'position' => stage.position_jabvox)
    end
  end

  def opt_task_boards(_params)
    JabvoxTaskBoard.where(account_id: @account.id).order(:position_jabvox, :name_jabvox)
                   .map { |b| option(b.id, b.name_jabvox) }
  end

  def opt_task_stages(params)
    board_id = require_dependency!(params[:boardId], 'task_stages', 'boardId')
    JabvoxTaskStage.where(account_id: @account.id, board_id: board_id).order(:position_jabvox)
                   .map { |s| option(s.id, s.name_jabvox, 'color' => s.color_jabvox) }
  end

  def opt_typifications(_params)
    JabvoxTypification.where(account_id: @account.id).order(:name).map do |t|
      option(t.id, t.name, 'description' => t.description, 'is_active' => t.is_active)
    end
  end

  def opt_campaigns(_params)
    JabvoxCampaign.where(account_id: @account.id).order(:name_jabvox)
                  .map { |c| option(c.id, c.name_jabvox, 'name' => c.name_jabvox) }
  end

  # Fuentes de datos externas de Analytics que están CONECTADAS (status ok): son
  # las únicas sobre las que el nodo de consulta puede leer.
  def opt_analytics_data_sources(_params)
    JabvoxAnalyticsDataSource.where(account_id: @account.id, status_jabvox: 'ok').order(:name_jabvox)
                             .map { |ds| option(ds.id, ds.name_jabvox, 'engine' => ds.engine_jabvox) }
  end

  # El estado se registra por NOMBRE (así lo guarda Jabvox), por eso value = nombre.
  def opt_management_states(_params)
    JabvoxManagementState.where(account_id: @account.id).order(:position_jabvox, :name_jabvox)
                         .map do |s|
      option(s.name_jabvox, s.name_jabvox, 'id' => s.id, 'color' => s.color_jabvox,
                                           'active' => s.is_active_jabvox)
    end
  end

  def opt_sms_providers(_params)
    JabvoxSmsProvider.where(account_id: @account.id).order(:name)
                     .map { |p| option(p.id, p.name, 'active' => p.active) }
  end

  def opt_calendar_external_people(_params)
    JabvoxCalendarExternalPerson.where(account_id: @account.id).order(:name).map do |p|
      label = p.email.present? ? "#{p.name} (#{p.email})" : p.name
      option(p.id, label, 'email' => p.email, 'phone_number' => p.phone_number)
    end
  end

  # El `meta` alimenta el autorrelleno de las líneas de pedido: al elegir un
  # producto se precargan precio unitario e impuesto.
  def opt_products(_params)
    JabvoxProduct.where(account_id: @account.id).where.not(active_jabvox: false)
                 .order(:name_jabvox).map do |p|
      option(p.id, p.name_jabvox,
             'name' => p.name_jabvox, 'unit_price' => p.price_jabvox.to_f,
             'tax_pct' => p.tax_percentage_jabvox.to_f, 'product_type' => p.product_type_jabvox)
    end
  end

  # El VALOR es la CLAVE, que es lo que se guarda en `jabvox_orders.status`.
  def opt_order_statuses(_params)
    JabvoxOrderStatusConfig.where(account_id: @account.id).order(:sort_order_jabvox).map do |s|
      option(s.key_jabvox, s.label_jabvox.presence || s.key_jabvox, 'color' => s.color_jabvox)
    end
  end

  private

  def option(value, label, meta = nil)
    result = { 'value' => value, 'label' => label.to_s }
    result['meta'] = meta if meta.present?
    result
  end

  def languages_by_name(templates)
    templates.group_by(&:name).transform_values do |group|
      group.filter_map { |t| t.language.presence }.uniq
    end
  end

  def require_dependency!(value, kind, param)
    return value if value.present?

    raise MissingDependency, "El kind '#{kind}' requiere el parámetro '#{param}'."
  end
end
