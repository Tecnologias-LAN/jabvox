# frozen_string_literal: true

module Jabvox
  module Reports
    # Totals table for a drill-down: the same filtered scope as the records list,
    # grouped into a breakdown (messages by status, managements by type, orders
    # by product, calls by status). Always respects the active filters, so the
    # totals reflect exactly what the table shows.
    #
    # Returns { total:, rows: [{ key:, label:, count:, sum: }] }.
    class BreakdownService
      def initialize(account:, definition:, range:, filters: {})
        @account = account
        @definition = definition
        @range = range
        @filters = filters || {}
      end

      def call
        { total: total_count, rows: breakdown_rows }
      end

      private

      def base_scope
        col = @definition[:date_column]
        scope = @definition[:scope].call(@account).except(:includes).reorder(nil)
        unless @definition[:skip_range]
          scope = scope.where("#{col} >= ? AND #{col} <= ?", @range.utc_begin, @range.utc_end)
        end
        FilterApplier.new(@definition, @filters, @range).apply(scope)
      end

      def total_count
        base_scope.count
      end

      def breakdown_rows
        bd = @definition[:breakdown]
        return [] unless bd

        case bd[:key]
        when 'status' then breakdown_message_status
        when 'management_state' then breakdown_management_state
        when 'product' then breakdown_product
        when 'call_status' then breakdown_call_status
        else []
        end
      end

      # Messages by status (sent/delivered/read/failed). Rails maps the enum, so
      # the grouped keys come back as status names (strings), not integers.
      def breakdown_message_status
        counts = base_scope.group('messages.status').count
        labels = { 'sent' => 'Enviado', 'delivered' => 'Entregado',
                   'read' => 'Leído', 'failed' => 'Fallido' }
        Message.statuses.keys.filter_map do |name|
          n = counts[name].to_i
          { key: name, label: labels[name] || name, count: n } if n.positive?
        end
      end

      # Managements grouped by management state (tipo de gestión).
      def breakdown_management_state
        counts = base_scope.group('jabvox_management_answers.jabvox_management_state_id').count
        names = JabvoxManagementState.where(account_id: @account.id, id: counts.keys.compact)
                                     .pluck(:id, :name_jabvox).to_h
        counts.map do |state_id, n|
          { key: state_id.to_s, label: names[state_id] || 'Sin gestión', count: n }
        end.sort_by { |r| -r[:count] }
      end

      # Orders broken down by product, via order items. Counts distinct orders
      # per product and sums the line totals.
      def breakdown_product
        order_ids = base_scope.reselect('jabvox_orders.id')
        rows = JabvoxOrderItem
               .where(jabvox_order_id: order_ids)
               .group(:jabvox_product_id, :name_snapshot)
               .select('jabvox_product_id, name_snapshot, COUNT(DISTINCT jabvox_order_id) AS cnt, ' \
                       'COALESCE(SUM(line_total), 0) AS sum_total')
        rows.map do |r|
          { key: r.jabvox_product_id.to_s, label: r.name_snapshot,
            count: r.cnt.to_i, sum: r.sum_total.to_f.round(2) }
        end.sort_by { |x| -x[:count] }
      end

      # Dialer calls by status.
      def breakdown_call_status
        counts = base_scope.group('jabvox_dialer_call_logs.status_jabvox').count
        labels = { 'answered' => 'Contestada', 'no_answer' => 'Sin respuesta',
                   'busy' => 'Ocupado', 'failed' => 'Fallida', 'initiated' => 'Iniciada' }
        counts.map do |status, n|
          { key: status, label: labels[status] || status, count: n }
        end.sort_by { |r| -r[:count] }
      end
    end
  end
end
