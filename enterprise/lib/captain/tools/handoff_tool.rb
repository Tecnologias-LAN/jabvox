class Captain::Tools::HandoffTool < Captain::Tools::BasePublicTool
  description 'Hand off the conversation to a human agent when unable to assist further'
  param :reason, type: 'string', desc: 'The reason why handoff is needed (optional)', required: false

  def perform(tool_context, reason: nil)
    conversation = find_conversation(tool_context.state)
    return 'Conversation not found' unless conversation

    # Log the handoff with reason
    log_tool_usage('tool_handoff', {
                     conversation_id: conversation.id,
                     reason: reason || 'Agent requested handoff'
                   })

    # Use existing handoff mechanism from ResponseBuilderJob
    trigger_handoff(tool_context, conversation, reason)

    "Conversation handed off to human support team#{" (Reason: #{reason})" if reason}"
  rescue StandardError => e
    JabvoxExceptionTracker.new(e).capture_exception
    'Failed to handoff conversation'
  end

  private

  def trigger_handoff(tool_context, conversation, reason)
    # post the reason as a private note
    note = conversation.messages.create!(
      message_type: :outgoing,
      private: true,
      sender: @assistant,
      account: conversation.account,
      inbox: conversation.inbox,
      content: reason
    )

    # Session capture attributes the run to this note so agents can inspect the
    # generation path on the handoff reason instead of the canned follow-up message.
    # A reason-less note has no content and never renders in the dashboard, so
    # leave it unrecorded and let capture fall back to the follow-up message.
    if reason.present?
      metadata = tool_context.state[:cw_metadata] ||= {}
      metadata[:handoff_note_id] = note.id
    end

    # Asigna al agente menos ocupado ANTES del bot_handoff!, para que el open!
    # posterior (que dispara el auto-assignment del inbox) no pise nuestra elección.
    assign_least_busy_agent(conversation)

    # Trigger the bot handoff (sets status to open + dispatches events)
    conversation.bot_handoff!

    # Send out of office message if applicable (since template messages were suppressed while Captain was handling)
    send_out_of_office_message_if_applicable(conversation)
  end

  # Elige, entre los agentes candidatos configurados (o los miembros del inbox si
  # no hay lista), el que tenga MENOS conversaciones abiertas, y le asigna la
  # conversación. No hace nada si no hay candidatos.
  def assign_least_busy_agent(conversation)
    candidates = handoff_candidate_ids(conversation)
    return if candidates.empty?

    agent_id = least_busy_agent_id(conversation.account, candidates)
    return if agent_id.nil?

    ::Conversations::AssignmentService.new(
      conversation: conversation, assignee_id: agent_id
    ).perform
    log_tool_usage('handoff_assigned', { conversation_id: conversation.id, assignee_id: agent_id })
  rescue StandardError => e
    # Si la asignación falla, no bloqueamos el handoff: la conversación queda
    # abierta y el auto-assignment del inbox (si existe) puede tomarla.
    JabvoxExceptionTracker.new(e).capture_exception
  end

  # IDs candidatos: lista configurada en el asistente; si está vacía, miembros del inbox.
  def handoff_candidate_ids(conversation)
    configured = @assistant.handoff_agents.pluck(:id)
    return configured if configured.any?

    conversation.inbox.inbox_members.pluck(:user_id)
  end

  # Agente con menos conversaciones abiertas (patrón BalancedSelector).
  def least_busy_agent_id(account, candidate_ids)
    counts = account.conversations.open
                    .where(assignee_id: candidate_ids)
                    .group(:assignee_id).count
    candidate_ids.min_by { |id| counts[id] || 0 }
  end

  def send_out_of_office_message_if_applicable(conversation)
    # Campaign conversations should never receive OOO templates — the campaign itself
    # serves as the initial outreach, and OOO would be confusing in that context.
    return if conversation.campaign.present?

    ::MessageTemplates::Template::OutOfOffice.perform_if_applicable(conversation)
  end

  # TODO: Future enhancement - Add team assignment capability
  # This tool could be enhanced to:
  # 1. Accept team_id parameter for routing to specific teams
  # 2. Set conversation priority based on handoff reason
  # 3. Add metadata for intelligent agent assignment
  # 4. Support escalation levels (L1 -> L2 -> L3)
  #
  # Example future signature:
  # param :team_id, type: 'string', desc: 'ID of team to assign conversation to', required: false
  # param :priority, type: 'string', desc: 'Priority level (low/medium/high/urgent)', required: false
  # param :escalation_level, type: 'string', desc: 'Support level (L1/L2/L3)', required: false
end
