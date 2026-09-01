# frozen_string_literal: true

module Jabvox
  module Reports
    # Single declarative source of truth for every report metric.
    #
    # Adding a metric means adding one entry here (and the mirrored column
    # definition in the frontend reportMetrics.js). Everything else — the
    # summary counts, the rollup job, the drill-down list and its serializer —
    # is generic over this registry, so no new controller/service code is needed
    # per metric.
    #
    # Each metric declares:
    #   key         - stable identifier used in URLs and the rollup table
    #   label       - human label (Spanish; the UI can still i18n)
    #   date_column - the DB column used both for range filtering and keyset
    #                 pagination (created_at, calldate, applied_at_jabvox, ...)
    #   scope       - ->(account) returning the base ActiveRecord relation,
    #                 already scoped to the account, WITHOUT date filtering
    #   user_column - column/expression to attribute a row to an agent, for the
    #                 per-agent rollup and the agent filter (nil = not attributable)
    #   inbox_column- column to attribute a row to an inbox (nil = none)
    #   serializer  - ->(record, ctx) returning the drill-down row hash
    #   sum_column  - optional column summed into the rollup (order totals, secs)
    module MetricRegistry
      module_function

      # Message enums (mirror app/models/message.rb): outgoing=1; status
      # sent=0/delivered=1/read=2/failed=3.
      OUTGOING = 1
      SENT_OK = [0, 1, 2].freeze
      FAILED = 3

      # Returns the full ordered list of metric definitions.
      def all
        [
          messages_sent,
          messages_failed,
          private_notes,
          managements,
          orders,
          calls,
          resolved,
          conversations,
          labels_added,
          labels_removed
        ]
      end

      def find(key)
        all.find { |m| m[:key] == key.to_s }
      end

      def keys
        all.map { |m| m[:key] }
      end

      # --- Metric definitions -------------------------------------------------

      def messages_sent
        # All outgoing (non-note) messages. The status filter narrows to
        # sent/delivered/read/failed; with no status filter it defaults to the
        # successful ones (sent+delivered+read) so the total matches the agents
        # report cell. The breakdown table splits by status.
        {
          key: 'messages_sent',
          label: 'Mensajes',
          date_column: 'messages.created_at',
          user_column: 'messages.sender_id',
          inbox_column: 'messages.inbox_id',
          sum_column: nil,
          status_column: 'messages.status',
          status_default: SENT_OK, # applied when no explicit status filter
          filters_config: [
            { key: 'status', type: 'select', label: 'Estado',
              options: [{ value: 'sent', label: 'Enviado' },
                        { value: 'delivered', label: 'Entregado' },
                        { value: 'read', label: 'Leído' },
                        { value: 'failed', label: 'Fallido' }] }
          ],
          breakdown: { key: 'status', label: 'Por estado' },
          scope: lambda do |account|
            Message.where(account_id: account.id, message_type: OUTGOING,
                          private: false, sender_type: 'User')
          end,
          serializer: ->(msg, ctx) { serialize_message(msg, ctx) }
        }
      end

      def messages_failed
        {
          key: 'messages_failed',
          label: 'Mensajes fallidos',
          date_column: 'messages.created_at',
          user_column: 'messages.sender_id',
          inbox_column: 'messages.inbox_id',
          sum_column: nil,
          scope: lambda do |account|
            Message.where(account_id: account.id, message_type: OUTGOING,
                          private: false, sender_type: 'User', status: FAILED)
          end,
          serializer: ->(msg, ctx) { serialize_message(msg, ctx) }
        }
      end

      def private_notes
        {
          key: 'private_notes',
          label: 'Notas privadas',
          date_column: 'messages.created_at',
          user_column: 'messages.sender_id',
          inbox_column: 'messages.inbox_id',
          sum_column: nil,
          filters_config: [], # only date
          breakdown: nil,
          scope: lambda do |account|
            # Private notes WITHOUT a management state (those are "gestiones").
            mgmt = JabvoxManagementAnswer.where(account_id: account.id)
                                         .where('jabvox_management_answers.message_id = messages.id').select(1)
            Message.where(account_id: account.id, private: true, sender_type: 'User')
                   .where('NOT EXISTS (?)', mgmt)
          end,
          serializer: ->(msg, ctx) { serialize_message(msg, ctx, note: true) }
        }
      end

      def managements
        # A "gestión" is ONE management event = one note/message that carries a
        # management state, NOT one answer row. In production a single gestión
        # has many answers (one per form question), all sharing the same
        # state_id, so counting answer rows overcounts massively. We collapse to
        # one row per message_id via DISTINCT ON, matching the agents-report cell
        # (which counts messages that have a management state).
        {
          key: 'managements',
          label: 'Gestiones',
          date_column: 'jabvox_management_answers.created_at',
          user_column: 'jabvox_management_answers.created_by_id',
          inbox_column: nil,
          sum_column: nil,
          management_state_column: 'jabvox_management_answers.jabvox_management_state_id',
          filters_config: [
            { key: 'management_state_id', type: 'select', label: 'Tipo de gestión',
              options_source: 'management_states' }
          ],
          breakdown: { key: 'management_state', label: 'Por gestión' },
          # Keep ONE representative answer per message_id (the lowest id), so
          # every downstream query (keyset list, count, breakdown) sees exactly
          # one row per gestión. Works with the standard keyset/count/group code.
          scope: lambda do |account|
            earlier = JabvoxManagementAnswer
                      .where('a2.message_id = jabvox_management_answers.message_id')
                      .where('a2.id < jabvox_management_answers.id')
                      .from('jabvox_management_answers a2').select(1)
            JabvoxManagementAnswer.where(account_id: account.id).where.not(message_id: nil)
                                  .where('NOT EXISTS (?)', earlier)
                                  .includes(:management_state, message: { conversation: :contact })
          end,
          serializer: ->(ans, ctx) { serialize_management(ans, ctx) }
        }
      end

      def orders
        # The agents report attributes orders by conversations.assignee_id, so
        # the drill-down joins conversations and filters/attributes by assignee
        # to keep the count and the per-agent filter consistent.
        {
          key: 'orders',
          label: 'Pedidos',
          date_column: 'jabvox_orders.created_at',
          user_column: 'conversations.assignee_id',
          inbox_column: nil,
          sum_column: 'jabvox_orders.total',
          doc_type_column: 'jabvox_orders.doc_type',
          product_join: true, # enables filter/breakdown by product via items
          filters_config: [
            { key: 'doc_type', type: 'select', label: 'Tipo',
              options: [{ value: 'QUOTE', label: 'Cotización' },
                        { value: 'SALE', label: 'Venta' }] },
            { key: 'product_id', type: 'select', label: 'Producto',
              options_source: 'products' }
          ],
          breakdown: { key: 'product', label: 'Por producto' },
          scope: lambda do |account|
            JabvoxOrder.where(account_id: account.id)
                       .joins(:conversation)
                       .includes(:contact, :jabvox_order_items, conversation: :assignee)
          end,
          serializer: ->(order, ctx) { serialize_order(order, ctx) }
        }
      end

      def calls
        # Same source as the agents report (jabvox_dialer_call_logs grouped by
        # agent_id_jabvox), so the drill-down count matches the cell and the
        # per-agent filter works.
        {
          key: 'calls',
          label: 'Llamadas',
          date_column: 'jabvox_dialer_call_logs.created_at',
          user_column: 'jabvox_dialer_call_logs.agent_id_jabvox',
          inbox_column: nil,
          sum_column: 'jabvox_dialer_call_logs.duration_jabvox',
          call_status_column: 'jabvox_dialer_call_logs.status_jabvox',
          filters_config: [
            { key: 'call_status', type: 'select', label: 'Estado',
              options: [{ value: 'answered', label: 'Contestada' },
                        { value: 'no_answer', label: 'Sin respuesta' },
                        { value: 'busy', label: 'Ocupado' },
                        { value: 'failed', label: 'Fallida' },
                        { value: 'initiated', label: 'Iniciada' }] }
          ],
          breakdown: { key: 'call_status', label: 'Por estado' },
          scope: lambda do |account|
            JabvoxDialerCallLog.where(account_id: account.id)
                               .includes(jabvox_dialer_campaign_contact: :contact)
          end,
          serializer: ->(log, ctx) { serialize_call(log, ctx) }
        }
      end

      def resolved
        # One row per resolution EVENT (not per conversation), attributed to the
        # assignee at resolution time (reporting_events.user_id). A conversation
        # resolved, reopened and resolved again counts twice — matching the
        # agents-report "Resueltos" cell.
        {
          key: 'resolved',
          label: 'Conversaciones resueltas',
          date_column: 'reporting_events.created_at',
          user_column: 'reporting_events.user_id',
          inbox_column: 'reporting_events.inbox_id',
          sum_column: nil,
          filters_config: [],
          breakdown: nil,
          scope: lambda do |account|
            ReportingEvent.where(account_id: account.id, name: 'conversation_resolved')
          end,
          serializer: ->(ev, ctx) { serialize_resolved(ev, ctx) }
        }
      end

      # Distinct conversations where the agent SENT at least one outgoing message
      # (the "personas con las que habló" count). One row per conversation. The
      # per-agent filter is applied via an EXISTS on the agent's messages, so it
      # matches the agents-report "Conversaciones" cell (COUNT DISTINCT).
      def conversations
        {
          key: 'conversations',
          label: 'Conversaciones',
          date_column: 'conversations.last_activity_at',
          user_column: 'conversations.assignee_id', # fallback; agent filter overridden below
          inbox_column: 'conversations.inbox_id',
          sum_column: nil,
          agent_via_messages: true, # filter by "agent sent a message here" EXISTS
          skip_range: true,         # date window applies inside the EXISTS, not to the conversation
          filters_config: [],
          breakdown: nil,
          scope: lambda do |account|
            Conversation.where(account_id: account.id).includes(:contact, :assignee)
          end,
          serializer: ->(conv, ctx) { serialize_conversation(conv, ctx) }
        }
      end

      def labels_added
        {
          key: 'labels_added',
          label: 'Etiquetas puestas',
          date_column: 'jabvox_conversation_label_logs.applied_at_jabvox',
          user_column: nil,
          inbox_column: nil,
          sum_column: nil,
          scope: lambda do |account|
            JabvoxConversationLabelLog.where(account_id: account.id)
          end,
          serializer: ->(log, ctx) { serialize_label(log, ctx, :applied) }
        }
      end

      def labels_removed
        {
          key: 'labels_removed',
          label: 'Etiquetas quitadas',
          date_column: 'jabvox_conversation_label_logs.removed_at_jabvox',
          user_column: nil,
          inbox_column: nil,
          sum_column: nil,
          scope: lambda do |account|
            JabvoxConversationLabelLog.where(account_id: account.id)
                                      .where.not(removed_at_jabvox: nil)
          end,
          serializer: ->(log, ctx) { serialize_label(log, ctx, :removed) }
        }
      end

      # --- Row serializers ----------------------------------------------------
      # ctx carries lookup caches (leads_by_contact, users_by_id, ...) built once
      # per page by RecordsService, so serializers never trigger N+1.

      def serialize_message(msg, ctx, note: false)
        conversation = msg.conversation
        contact = conversation&.contact
        sender = ctx[:users_by_id][msg.sender_id]
        error = msg.content_attributes&.dig('external_error') if msg.status == 'failed'
        base = {
          id: msg.id,
          created_at: msg.created_at,
          lead: lead_view(contact, ctx),
          inbox_id: msg.inbox_id,
          inbox_name: ctx[:inboxes_by_id][msg.inbox_id]&.name,
          agent_id: msg.sender_id,
          agent_name: sender&.name,
          content: truncate_text(msg.content),
          content_full: msg.content,
          conversation_url: conversation_url(ctx, conversation)
        }
        note ? base : base.merge(status: msg.status, error_reason: error)
      end

      def serialize_management(ans, ctx)
        conversation = ans.message&.conversation
        contact = conversation&.contact
        {
          id: ans.id,
          created_at: ans.created_at,
          lead: lead_view(contact, ctx),
          agent_id: ans.created_by_id,
          agent_name: ctx[:users_by_id][ans.created_by_id]&.name,
          management_type: ans.management_state&.name_jabvox,
          result: truncate_text(ans.value),
          result_full: ans.value,
          conversation_url: conversation_url(ctx, conversation)
        }
      end

      def serialize_order(order, ctx)
        contact = order.contact
        assignee = order.conversation&.assignee
        {
          id: order.id,
          created_at: order.created_at,
          lead: lead_view(contact, ctx),
          agent_id: assignee&.id,
          agent_name: assignee&.name,
          order_ref: order.alegra_number.presence || order.id.to_s,
          amount: order.total.to_s,
          status: order.status,
          doc_type: order.doc_type,
          conversation_url: conversation_url(ctx, order.conversation)
        }
      end

      def serialize_call(log, ctx)
        contact = log.jabvox_dialer_campaign_contact&.contact
        {
          id: log.id,
          created_at: log.created_at,
          lead: dialer_lead_view(log, contact, ctx),
          agent_id: log.agent_id_jabvox,
          agent_name: ctx[:users_by_id][log.agent_id_jabvox]&.name,
          direction: 'outbound', # dialer calls are outbound
          duration: log.duration_jabvox.to_i,
          result: log.status_jabvox,
          conversation_url: contact ? nil : nil
        }
      end

      def serialize_resolved(ev, ctx)
        conversation = ctx[:conversations_by_id][ev.conversation_id]
        contact = conversation&.contact
        {
          id: ev.id,
          created_at: ev.created_at,
          lead: lead_view(contact, ctx),
          agent_id: ev.user_id,
          agent_name: ctx[:users_by_id][ev.user_id]&.name,
          resolution_seconds: ev.value.to_i,
          first_response_seconds: nil,
          conversation_url: conversation_url(ctx, conversation)
        }
      end

      def serialize_label(log, ctx, kind)
        conversation = ctx[:conversations_by_id][log.conversation_id]
        contact = conversation&.contact
        {
          id: log.id,
          created_at: kind == :applied ? log.applied_at_jabvox : log.removed_at_jabvox,
          lead: lead_view(contact, ctx),
          label: log.label_jabvox,
          conversation_url: conversation_url(ctx, conversation)
        }
      end

      # One row per conversation (the person the agent talked to).
      def serialize_conversation(conv, ctx)
        {
          id: conv.id,
          created_at: conv.last_activity_at || conv.created_at,
          lead: lead_view(conv.contact, ctx),
          agent_name: conv.assignee&.name,
          status: conv.status,
          conversation_url: conversation_url(ctx, conv)
        }
      end

      # --- Shared view helpers ------------------------------------------------

      # The "lead visual" every drill-down row shares: name, avatar, channel.
      def lead_view(contact, ctx)
        return nil unless contact

        lead = ctx[:leads_by_contact][contact.id]
        {
          contact_id: contact.id,
          lead_id: lead&.id,
          lead_number: lead&.lead_number,
          name: contact.name,
          phone: contact.phone_number,
          avatar_url: contact.respond_to?(:avatar_url) ? contact.avatar_url : nil,
          channel: ctx[:channel_by_contact]&.dig(contact.id)
        }
      end

      # Dialer call lead visual: the dialed CRM contact when known, else just
      # the phone that was dialed.
      def dialer_lead_view(log, contact, ctx)
        return lead_view(contact, ctx).merge(channel: 'voice') if contact

        { contact_id: nil, lead_id: nil, lead_number: nil, name: nil,
          phone: log.phone_jabvox, avatar_url: nil, channel: 'voice' }
      end

      def conversation_url(ctx, conversation)
        return nil unless conversation&.display_id

        "/app/accounts/#{ctx[:account_id]}/conversations/#{conversation.display_id}"
      end

      def truncate_text(text, length: 140)
        return nil if text.blank?

        text.length > length ? "#{text[0, length]}…" : text
      end
    end
  end
end
