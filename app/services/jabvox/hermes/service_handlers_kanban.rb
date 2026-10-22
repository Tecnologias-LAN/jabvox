# frozen_string_literal: true

# Handlers de Kanban (tablero, movimiento de tarjetas y automatizaciones de columna) y de
# Calendario (personas externas). Es lo que faltaba para que el agente pueda "ver el tablero,
# mover tarjetas, ver estados y crear automatizaciones", no solo listar embudos.
#
# Reglas de siempre: todo bajo @account, ninguno borra, y mover una tarjeta se registra con
# el usuario que lo pidió (moved_by) para que la trazabilidad no se pierda.
#
module Jabvox::Hermes::ServiceHandlersKanban
  # ==========================================================================
  # Columnas del embudo
  # ==========================================================================

  def list_kanban_stages(params)
    scope = @account.jabvox_kanban_stages
    scope = scope.where(jabvox_kanban_funnel_id: params[:funnel_id]) if params[:funnel_id].present?
    scope.order(:position_jabvox).limit(capped_limit(params)).map { |s| kanban_stage_view(s) }
  end

  def kanban_stage_view(stage)
    { id: stage.id, funnel_id: stage.jabvox_kanban_funnel_id, name: stage.name_jabvox,
      description: stage.description_jabvox, position: stage.position_jabvox, color: stage.color_jabvox,
      auto_advance: stage.auto_advance_enabled, auto_advance_hours: stage.auto_advance_hours,
      auto_advance_target_stage_id: stage.auto_advance_target_stage_id }
  end

  # ==========================================================================
  # Tablero: qué hay en cada columna
  # ==========================================================================

  # Vista del tablero de un embudo: cada columna con las conversaciones colocadas en ella.
  # Es lo que permite responder "qué hay en la etapa X" o "cuántos leads van por cerrar".
  def get_kanban_board(params)
    funnel = @account.jabvox_kanban_funnels.find(params[:funnel_id])
    stages = @account.jabvox_kanban_stages.where(jabvox_kanban_funnel_id: funnel.id).order(:position_jabvox)
    placements = JabvoxKanbanConversationStage.where(account_id: @account.id, jabvox_kanban_funnel_id: funnel.id)
                                              .group(:jabvox_kanban_stage_id).count
    {
      funnel: { id: funnel.id, name: funnel.try(:name_jabvox) || funnel.try(:name) },
      stages: stages.map { |s| kanban_stage_view(s).merge(cards_count: placements[s.id].to_i) },
      total_cards: placements.values.sum
    }
  end

  # Conversaciones colocadas en UNA columna, con su contacto — el detalle del tablero.
  def get_kanban_stage_cards(params)
    stage = @account.jabvox_kanban_stages.find(params[:stage_id])
    placements = JabvoxKanbanConversationStage
                 .where(account_id: @account.id, jabvox_kanban_stage_id: stage.id)
                 .order(updated_at: :desc).limit(capped_limit(params))
    convs = @account.conversations.where(id: placements.map(&:conversation_id)).includes(:contact).index_by(&:id)
    placements.filter_map do |p|
      conv = convs[p.conversation_id]
      next if conv.nil?

      { conversation_id: conv.display_id, contact: conv.contact&.name, status: conv.status,
        assignee_id: conv.assignee_id, moved_at: p.updated_at }
    end
  end

  # Mueve una conversación a otra columna del embudo. Deja constancia de quién la movió.
  def move_kanban_card(params)
    stage = @account.jabvox_kanban_stages.find(params[:stage_id])
    conversation = @account.conversations.find_by!(display_id: params[:conversation_id])
    placement = JabvoxKanbanConversationStage.find_or_initialize_by(
      conversation_id: conversation.id, jabvox_kanban_funnel_id: stage.jabvox_kanban_funnel_id
    )
    placement.assign_attributes(jabvox_kanban_stage_id: stage.id, account_id: @account.id,
                                moved_by_id: @user&.id)
    placement.save!
    { conversation_id: conversation.display_id, stage_id: stage.id, stage_name: stage.name_jabvox }
  end

  # ==========================================================================
  # Automatizaciones de columna
  # ==========================================================================

  def list_kanban_stage_automations(params)
    scope = filter_by(@account.jabvox_kanban_stage_automations, params, :jabvox_kanban_stage_id, :active)
    scope.order(:id).limit(capped_limit(params)).map { |a| kanban_automation_view(a) }
  end

  def create_kanban_stage_automation(params)
    # La etapa dueña se resuelve dentro de la cuenta (find en @account), no cruda desde params:
    # así una etapa de otra cuenta da RecordNotFound en vez de crearse atada a ella.
    stage = @account.jabvox_kanban_stages.find(params[:stage_id])
    a = @account.jabvox_kanban_stage_automations.new(
      build_kanban_automation_attrs(params).merge(jabvox_kanban_stage_id: stage.id)
    )
    a.active = params.key?(:active) ? params[:active] : true
    a.created_by_id = @user&.id
    a.save!
    kanban_automation_view(a)
  end

  def update_kanban_stage_automation(params)
    a = @account.jabvox_kanban_stage_automations.find(params[:id])
    a.update!(build_kanban_automation_attrs(params))
    kanban_automation_view(a)
  end

  # Mapea los params de la tool a las columnas reales del modelo. Incluye el canal de
  # PLANTILLA de WhatsApp (template_name/language/params) y el disparador por tiempo
  # (trigger_value/unit), antes ausentes: sin ellos Hermes no podía crear automatizaciones
  # de columna que envíen plantillas con variables. template_params es el mapeo {var => {source,field}}.
  def build_kanban_automation_attrs(params)
    map = { name: :name, automation_type: :automation_type, channel_type: :channel_type,
            message_body: :message_body, inbox_id: :inbox_id, trigger_hours: :trigger_hours,
            target_stage_id: :target_stage_id, active: :active,
            email_template_id: :jabvox_email_template_id, sms_provider_id: :jabvox_sms_provider_id,
            template_name: :template_name_jabvox, template_language: :template_language_jabvox,
            template_params: :template_params_jabvox,
            trigger_value: :trigger_value_jabvox, trigger_unit: :trigger_unit_jabvox }
    map.each_with_object({}) { |(from, to), out| out[to] = params[from] if params.key?(from) }
  end

  def kanban_automation_view(automation)
    { id: automation.id, stage_id: automation.jabvox_kanban_stage_id, name: automation.name,
      automation_type: automation.automation_type, channel_type: automation.channel_type,
      inbox_id: automation.inbox_id, trigger_hours: automation.trigger_hours,
      target_stage_id: automation.target_stage_id, active: automation.active,
      template_name: automation.template_name_jabvox,
      template_language: automation.template_language_jabvox,
      template_params: automation.template_params_jabvox,
      trigger_value: automation.trigger_value_jabvox, trigger_unit: automation.trigger_unit_jabvox }
  end

  # ==========================================================================
  # Calendario: personas externas
  # ==========================================================================

  def list_calendar_external_people(params)
    @account.jabvox_calendar_external_people.order(:id).limit(capped_limit(params)).map { |p| external_person_view(p) }
  end
end
