# frozen_string_literal: true

module Jabvox
  module Reports
    # Applies the shared filters (inbox, agent, conversation status) to a metric
    # scope, using the column metadata each metric declares. A filter that a
    # metric cannot support (e.g. inbox on CDR, which has no inbox_id) is simply
    # skipped rather than producing an empty/broken query.
    class FilterApplier
      # `range` is only needed for metrics whose agent filter is an EXISTS over
      # another table (conversations), so the date window applies to the agent's
      # messages, not to the parent row.
      def initialize(definition, filters, range = nil)
        @definition = definition
        @filters = filters || {}
        @range = range
      end

      def apply(scope)
        scope = apply_inbox(scope)
        scope = apply_agent(scope)
        scope = apply_status(scope)
        scope = apply_management_state(scope)
        scope = apply_doc_type(scope)
        scope = apply_product(scope)
        scope = apply_call_status(scope)
        apply_search(scope)
      end

      private

      # Message status filter (sent/delivered/read/failed). When absent, the
      # metric's status_default keeps the total consistent with the report cell.
      def apply_status(scope)
        col = @definition[:status_column]
        return scope unless col

        wanted = Array(@filters[:status]).map(&:to_s).reject(&:blank?)
        if wanted.any?
          codes = wanted.map { |s| Message.statuses[s] }.compact
          return scope.where("#{col} IN (?)", codes) if codes.any?
        end
        default = @definition[:status_default]
        default ? scope.where("#{col} IN (?)", default) : scope
      end

      def apply_management_state(scope)
        col = @definition[:management_state_column]
        return scope unless col

        id = @filters[:management_state_id].to_i
        return scope if id.zero?

        scope.where("#{col} = ?", id)
      end

      def apply_doc_type(scope)
        col = @definition[:doc_type_column]
        return scope unless col

        value = @filters[:doc_type].to_s
        return scope if value.blank?

        scope.where("#{col} = ?", value)
      end

      # Product filter for orders: keep orders that have an item for the product.
      def apply_product(scope)
        return scope unless @definition[:product_join]

        id = @filters[:product_id].to_i
        return scope if id.zero?

        items = JabvoxOrderItem.where('jabvox_order_items.jabvox_order_id = jabvox_orders.id')
                               .where(jabvox_product_id: id).select(1)
        scope.where('EXISTS (?)', items)
      end

      def apply_call_status(scope)
        col = @definition[:call_status_column]
        return scope unless col

        value = @filters[:call_status].to_s
        return scope if value.blank?

        scope.where("#{col} = ?", value)
      end

      def apply_inbox(scope)
        ids = Array(@filters[:inbox_ids]).map(&:to_i).reject(&:zero?)
        return scope if ids.empty?

        col = @definition[:inbox_column]
        return scope unless col

        scope.where("#{col} IN (?)", ids)
      end

      def apply_agent(scope)
        ids = Array(@filters[:agent_ids]).map(&:to_i).reject(&:zero?)
        return scope if ids.empty?

        # "Conversaciones" attributes an agent by whether they SENT a message in
        # the conversation within the date window, not by a column — this makes
        # the count match the agents-report "Conversaciones" cell exactly.
        if @definition[:agent_via_messages]
          msgs = Message.where('messages.conversation_id = conversations.id')
                        .where(message_type: 1, private: false, sender_type: 'User')
                        .where(sender_id: ids)
          if @range
            msgs = msgs.where('messages.created_at >= ? AND messages.created_at <= ?',
                              @range.utc_begin, @range.utc_end)
          end
          return scope.where('EXISTS (?)', msgs.select(1))
        end

        col = @definition[:user_column]
        return scope unless col

        scope.where("#{col} IN (?)", ids)
      end

      # Free-text search over the metric's textual column, only for metrics that
      # declare one. Uses the pg_trgm GIN index on messages.content where present
      # (never a bare ILIKE '%...%' on an unindexed column).
      def apply_search(scope)
        term = @filters[:search].to_s.strip
        return scope if term.blank?

        case @definition[:key]
        when 'messages_sent', 'messages_failed', 'private_notes'
          scope.where('messages.content ILIKE ?', "%#{sanitize_like(term)}%")
        else
          scope
        end
      end

      def sanitize_like(term)
        term.gsub(/[\\%_]/) { |c| "\\#{c}" }
      end
    end
  end
end
