# frozen_string_literal: true

module Jabvox
  module Reports
    # Resolves report date ranges in the ACCOUNT timezone.
    #
    # accounts has no timezone column today, so the zone is configurable via
    # ENV JABVOX_REPORTS_TIMEZONE (default America/Bogota). Centralizing it here
    # means adding a per-account column later only changes this one file.
    #
    # Presets and custom ranges both resolve to a UTC [begin, end] pair used for
    # SQL filtering, plus the previous equivalent period for the % change.
    class TimeRange
      MAX_RANGE_DAYS = 366 # hard limit (section 5): reject spans over ~12 months

      PRESETS = %w[today yesterday last_7_days last_30_days last_90_days this_month last_month custom].freeze

      attr_reader :zone, :from, :to, :preset

      def self.account_zone(_account = nil)
        ActiveSupport::TimeZone[ENV.fetch('JABVOX_REPORTS_TIMEZONE', 'America/Bogota')] ||
          ActiveSupport::TimeZone['UTC']
      end

      # Raises Jabvox::Reports::RangeTooLargeError when the span exceeds the cap.
      def initialize(account:, preset: nil, from: nil, to: nil)
        @zone = self.class.account_zone(account)
        @preset = (preset.presence || 'last_30_days').to_s
        resolve!(from, to)
        validate_span!
      end

      # UTC boundaries for SQL BETWEEN filtering.
      def utc_begin = @from.utc
      def utc_end = @to.utc

      # Equivalent immediately-preceding window, same length.
      def previous
        length = @to - @from
        self.class.allocate.tap do |r|
          r.instance_variable_set(:@zone, @zone)
          r.instance_variable_set(:@preset, "#{@preset}_prev")
          r.instance_variable_set(:@from, @from - length)
          r.instance_variable_set(:@to, @from)
        end
      end

      # Days fully in the past (safe to read from closed-day rollups) vs the
      # day still in progress (must be queried live).
      def closed_days
        today = @zone.today
        (@from.to_date...[@to.to_date, today].min).to_a
      end

      def open_day
        today = @zone.today
        @to.to_date >= today ? today : nil
      end

      def to_meta
        { from: @from.iso8601, to: @to.iso8601, timezone: @zone.name, preset: @preset }
      end

      private

      def resolve!(from, to)
        now = Time.now.in_time_zone(@zone)
        case @preset
        when 'today'       then day_range(now)
        when 'yesterday'   then day_range(now - 1.day)
        when 'last_7_days'  then span(now, 7)
        when 'last_30_days' then span(now, 30)
        when 'last_90_days' then span(now, 90)
        when 'this_month'  then @from = now.beginning_of_month; @to = now.end_of_day
        when 'last_month'
          prev = now - 1.month
          @from = prev.beginning_of_month
          @to = prev.end_of_month
        else # custom
          @from = parse(from)&.beginning_of_day || span_start(now, 30)
          @to = parse(to)&.end_of_day || now.end_of_day
        end
      end

      def day_range(moment)
        @from = moment.beginning_of_day
        @to = moment.end_of_day
      end

      def span(now, days)
        @from = span_start(now, days)
        @to = now.end_of_day
      end

      def span_start(now, days) = (now - (days - 1).days).beginning_of_day

      def parse(str)
        return nil if str.blank?

        @zone.parse(str.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      def validate_span!
        return if (@to.to_date - @from.to_date).to_i <= MAX_RANGE_DAYS

        raise RangeTooLargeError, "Rango máximo de #{MAX_RANGE_DAYS} días excedido"
      end
    end
  end
end
