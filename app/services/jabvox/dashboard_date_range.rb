# frozen_string_literal: true

class Jabvox::DashboardDateRange
  MAX_DAYS = 366

  attr_reader :from, :to, :to_exclusive, :time_zone, :now

  def initialize(account:, date_from: nil, date_to: nil)
    @time_zone = Jabvox::Reports::TimeRange.account_zone(account)
    @now = Time.current.in_time_zone(@time_zone)
    @from_date = selected_date(date_from, @now.to_date)
    @to_date = selected_date(date_to, @from_date)
    validate_order!
    validate_length!
    set_time_boundaries
  end

  def time_range
    from...to_exclusive
  end

  def days
    (@from_date..@to_date).to_a
  end

  def to_meta
    {
      date_from: @from_date.iso8601,
      date_to: @to_date.iso8601,
      time_zone: time_zone.name,
      max_days: MAX_DAYS
    }
  end

  private

  def selected_date(value, fallback)
    parse_date(value.presence || fallback.iso8601)
  end

  def parse_date(value)
    return Date.iso8601(value) if value.is_a?(String) && value.match?(/\A\d{4}-\d{2}-\d{2}\z/)

    raise ArgumentError, 'Las fechas deben tener formato AAAA-MM-DD'
  rescue Date::Error
    raise ArgumentError, 'La fecha no es válida'
  end

  def validate_order!
    return if @to_date >= @from_date

    raise ArgumentError, 'La fecha final no puede ser anterior a la fecha inicial'
  end

  def validate_length!
    return if (@to_date - @from_date).to_i < MAX_DAYS

    raise ArgumentError, "El rango máximo es de #{MAX_DAYS} días"
  end

  def set_time_boundaries
    @from = @time_zone.local(@from_date.year, @from_date.month, @from_date.day)
    next_day = @to_date.next_day
    @to_exclusive = @time_zone.local(next_day.year, next_day.month, next_day.day)
    @to = @to_exclusive - 1.second
  end
end
