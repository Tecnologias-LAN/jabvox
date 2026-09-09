# frozen_string_literal: true

# Calcula los huecos libres de un agente en un rango de fechas, combinando su
# horario laboral (JabvoxAgentAvailability, por día de la semana) con las citas
# ya agendadas en el calendario (JabvoxCalendarEvent). Devuelve slots discretos
# de la duración configurada por el agente, listos para ofrecer al agendar.
#
# Uso:
#   Jabvox::AgentAvailabilityService
#     .new(account:, user:, from: Date.today, to: Date.today + 6, timezone: 'America/Bogota')
#     .free_slots
#   => [{ start_at:, end_at: }, ...]  (en la zona horaria dada)
module Jabvox
  class AgentAvailabilityService
    # Tope de slots devueltos para no inundar al LLM ni la UI.
    MAX_SLOTS = 60

    def initialize(account:, user:, from:, to:, timezone: 'UTC', now: nil)
      @account = account
      @user = user
      @from = from.to_date
      @to = to.to_date
      @tz = ActiveSupport::TimeZone[timezone] || ActiveSupport::TimeZone['UTC']
      @now = now || Time.current
    end

    # true si el agente tiene al menos un día con horario laboral configurado.
    def configured?
      availabilities.any?
    end

    def free_slots
      return [] unless configured?

      busy = busy_intervals
      slots = []

      (@from..@to).each do |date|
        availabilities_for(date.wday).each do |av|
          slots.concat(day_slots(date, av, busy))
          break if slots.size >= MAX_SLOTS
        end
        break if slots.size >= MAX_SLOTS
      end

      slots.first(MAX_SLOTS)
    end

    private

    # Slots libres de un día concreto para una franja laboral, descontando lo ocupado.
    def day_slots(date, availability, busy)
      cursor = minutes_to_time(date, availability.start_minute)
      day_end = minutes_to_time(date, availability.end_minute)
      step = availability.slot_minutes.minutes
      result = []

      while cursor + step <= day_end
        slot_end = cursor + step
        # Descarta slots en el pasado y los que solapan una cita existente.
        result << { start_at: cursor, end_at: slot_end } if cursor > @now && !overlaps_any?(cursor, slot_end, busy)
        cursor = slot_end
      end

      result
    end

    def overlaps_any?(start_at, end_at, busy)
      busy.any? { |b| start_at < b[:end_at] && end_at > b[:start_at] }
    end

    # Citas ya agendadas del agente en el rango (no canceladas) como intervalos ocupados.
    def busy_intervals
      window_start = @tz.local(@from.year, @from.month, @from.day, 0, 0, 0)
      window_end = @tz.local(@to.year, @to.month, @to.day, 23, 59, 59)

      @account.jabvox_calendar_events
              .for_user(@user.id)
              .where.not(status: :cancelled)
              .where(start_at: window_start..window_end)
              .pluck(:start_at, :end_at, :all_day)
              .map { |start_at, end_at, all_day| event_interval(start_at, end_at, all_day) }
    end

    # Una cita normal ocupa [start, end); una all_day ocupa el día completo.
    def event_interval(start_at, end_at, all_day)
      return { start_at: start_at.in_time_zone(@tz), end_at: end_at.in_time_zone(@tz) } unless all_day

      day = start_at.in_time_zone(@tz).to_date
      { start_at: @tz.local(day.year, day.month, day.day, 0, 0, 0),
        end_at: @tz.local(day.year, day.month, day.day, 23, 59, 59) }
    end

    def availabilities
      @availabilities ||= JabvoxAgentAvailability
                          .active
                          .where(account_id: @account.id, user_id: @user.id)
                          .to_a
    end

    def availabilities_for(wday)
      availabilities.select { |a| a.day_of_week == wday }
    end

    def minutes_to_time(date, minutes)
      @tz.local(date.year, date.month, date.day, minutes / 60, minutes % 60, 0)
    end
  end
end
