# frozen_string_literal: true

module Jabvox
  module Reports
    # Drill-down list for a single metric: keyset (cursor) pagination over the
    # source table, plus a context bundle so serializers never trigger N+1.
    #
    # Pagination (section 3): ordered by (date_column, id) DESC and paged by a
    # cursor built from the last row's (date, id), NOT OFFSET. total_count is
    # computed once and cached in Redis for a few minutes.
    class RecordsService
      PAGE_SIZES = [25, 50, 100].freeze
      DEFAULT_PAGE_SIZE = 25
      COUNT_CACHE_TTL = 3.minutes
      COUNT_HARD_LIMIT = 100_000 # count is exact up to here, then reported as "≥"

      Result = Struct.new(:data, :total_count, :total_is_approx, :next_cursor, :has_more, keyword_init: true)

      def initialize(account:, definition:, range:, filters: {}, cursor: nil, per_page: nil, order_dir: 'desc')
        @account = account
        @definition = definition
        @range = range
        @filters = filters || {}
        @cursor = cursor
        @per_page = sanitize_page_size(per_page)
        @order_dir = order_dir == 'asc' ? 'asc' : 'desc'
      end

      def call
        scope = base_scope
        scope = apply_cursor(scope) if @cursor.present?
        rows = scope.limit(@per_page + 1).to_a

        has_more = rows.size > @per_page
        rows = rows.first(@per_page)
        ctx = build_context(rows)

        Result.new(
          data: rows.map { |row| @definition[:serializer].call(row, ctx) },
          total_count: total_count,
          total_is_approx: total_count == COUNT_HARD_LIMIT,
          next_cursor: has_more ? encode_cursor(rows.last) : nil,
          has_more: has_more
        )
      end

      private

      def base_scope
        col = @definition[:date_column]
        scope = @definition[:scope].call(@account)
        unless @definition[:skip_range]
          scope = scope.where("#{col} >= ? AND #{col} <= ?", @range.utc_begin, @range.utc_end)
        end
        scope = FilterApplier.new(@definition, @filters, @range).apply(scope)
        scope.reorder(Arel.sql("#{col} #{@order_dir.upcase}, #{id_column} #{@order_dir.upcase}"))
      end

      # Keyset: (date, id) strictly past the cursor tuple. Uses a row-value
      # comparison so it maps to the composite keyset index.
      def apply_cursor(scope)
        date_val, id_val = decode_cursor
        return scope unless date_val

        col = @definition[:date_column]
        op = @order_dir == 'desc' ? '<' : '>'
        scope.where("(#{col}, #{id_column}) #{op} (?, ?)", date_val, id_val)
      end

      def total_count
        @total_count ||= begin
          cached = read_count_cache
          if cached
            cached
          else
            value = base_count.limit(COUNT_HARD_LIMIT).count
            write_count_cache(value)
            value
          end
        end
      end

      # Count without ordering/limit; capped so a pathological filter can't run
      # an unbounded COUNT(*).
      def base_count
        col = @definition[:date_column]
        scope = @definition[:scope].call(@account)
        unless @definition[:skip_range]
          scope = scope.where("#{col} >= ? AND #{col} <= ?", @range.utc_begin, @range.utc_end)
        end
        FilterApplier.new(@definition, @filters, @range).apply(scope).reorder(nil)
      end

      # --- Context bundle (kills N+1) -----------------------------------------
      # Collects every id the page's serializers will need and loads them in a
      # handful of queries, keyed for O(1) lookup.
      def build_context(rows)
        conversations = collect_conversations(rows)
        contact_ids = conversations.filter_map(&:contact_id).uniq
        leads = contact_ids.any? ? JabvoxLead.where(account_id: @account.id, contact_id: contact_ids).index_by(&:contact_id) : {}
        user_ids = collect_user_ids(rows)
        inbox_ids = rows.map { |r| r.respond_to?(:inbox_id) ? r.inbox_id : nil }.compact.uniq

        {
          account_id: @account.id,
          conversations_by_id: conversations.index_by(&:id),
          leads_by_contact: leads,
          users_by_id: user_ids.any? ? User.where(id: user_ids).index_by(&:id) : {},
          inboxes_by_id: inbox_ids.any? ? @account.inboxes.where(id: inbox_ids).index_by(&:id) : {},
          channel_by_contact: {}
        }
      end

      # For metrics whose records reference a conversation_id but weren't eager
      # loaded (resolved events, label logs), load conversations + contacts once.
      # When the rows ARE conversations (the "conversations" metric), use them
      # directly.
      def collect_conversations(rows)
        return rows if rows.first.is_a?(Conversation)

        preloaded = rows.filter_map do |row|
          row.conversation if row.respond_to?(:conversation) && row.association(:conversation).loaded?
        rescue StandardError
          nil
        end
        ids = rows.map { |r| r.respond_to?(:conversation_id) ? r.conversation_id : nil }.compact.uniq
        loaded_ids = preloaded.map(&:id)
        missing = ids - loaded_ids
        extra = missing.any? ? Conversation.where(account_id: @account.id, id: missing).includes(:contact).to_a : []
        (preloaded + extra).uniq(&:id)
      end

      def collect_user_ids(rows)
        rows.flat_map do |row|
          [row.try(:sender_id), row.try(:created_by_id), row.try(:user_id),
           row.try(:assignee_id), row.try(:agent_id_jabvox),
           row.try(:conversation)&.assignee_id]
        end.compact.uniq
      end

      # --- Cursor encoding ----------------------------------------------------
      def id_column
        @definition[:date_column].split('.').first + '.id'
      end

      def encode_cursor(row)
        date_val = row.public_send(date_attr)
        Base64.urlsafe_encode64({ d: date_val&.iso8601(6), i: row.id }.to_json)
      end

      def decode_cursor
        parsed = JSON.parse(Base64.urlsafe_decode64(@cursor), symbolize_names: true)
        [parsed[:d], parsed[:i]]
      rescue StandardError
        [nil, nil]
      end

      def date_attr
        @definition[:date_column].split('.').last
      end

      def sanitize_page_size(value)
        size = value.to_i
        PAGE_SIZES.include?(size) ? size : DEFAULT_PAGE_SIZE
      end

      # --- count cache --------------------------------------------------------
      def count_cache_key
        payload = { m: @definition[:key], r: @range.to_meta, f: @filters }.to_json
        "jabvox:reports:count:#{@account.id}:#{Digest::MD5.hexdigest(payload)}"
      end

      def read_count_cache
        raw = Redis::Alfred.get(count_cache_key)
        raw&.to_i
      rescue StandardError
        nil
      end

      def write_count_cache(value)
        Redis::Alfred.setex(count_cache_key, value.to_s, COUNT_CACHE_TTL.to_i)
      rescue StandardError
        nil
      end
    end
  end
end
