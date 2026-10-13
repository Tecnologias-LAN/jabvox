# frozen_string_literal: true

class Jabvox::DashboardSummaryService
  def initialize(account:, date_range:, modules:, ticket_scope:)
    @account = account
    @date_range = date_range
    @modules = modules
    @ticket_scope = ticket_scope
  end

  def call
    daily = {}
    modules = module_summaries(daily)

    {
      filters: @date_range.to_meta,
      modules: modules,
      daily: daily_rows(daily)
    }
  end

  private

  def module_summaries(daily)
    modules = { messages: messages_summary(daily) }
    summary_builders(daily).slice(*@modules).each do |key, builder|
      modules[key] = builder.call
    end
    modules
  end

  def summary_builders(daily)
    {
      calls: -> { calls_summary(daily) },
      campaigns: -> { campaigns_summary },
      whatsapp: -> { whatsapp_summary },
      tickets: -> { tickets_summary(daily) },
      events: -> { events_summary(daily) },
      tasks: -> { tasks_summary },
      kanban: -> { kanban_summary },
      orders: -> { orders_summary },
      sms: -> { sms_summary },
      email: -> { email_summary },
      forms: -> { forms_summary }
    }
  end

  def daily_rows(daily)
    @date_range.days.map do |day|
      {
        date: day.iso8601,
        messages: daily.dig(:messages, day).to_i,
        calls: daily.dig(:calls, day).to_i,
        tickets: daily.dig(:tickets, day).to_i,
        events: daily.dig(:events, day).to_i
      }
    end
  end

  def messages_summary(daily)
    messages = Message.where(account_id: @account.id, private: false, created_at: @date_range.time_range)
    incoming = messages.where(message_type: :incoming).count
    outgoing = messages.where(message_type: :outgoing, sender_type: 'User').count

    daily[:messages] = daily_counts(
      messages.where(message_type: :incoming).or(
        messages.where(message_type: :outgoing, sender_type: 'User')
      ),
      :created_at
    )

    { incoming: incoming, outgoing: outgoing }
  end

  def calls_summary(daily)
    config = @account.jabvox_cdr_config
    records = JabvoxCdrRecord.for_account(@account.id)
    local_from = @date_range.from.strftime('%Y-%m-%d %H:%M:%S')
    local_to = @date_range.to_exclusive.strftime('%Y-%m-%d %H:%M:%S')
    range_records = records.where(
      'calldate >= ? AND calldate < ?',
      local_from,
      local_to
    )

    daily[:calls] = daily_counts(range_records, :calldate, local_date: true)

    {
      configured: config&.mysql_host.present?,
      total: range_records.count,
      answered: range_records.where(disposition: 'ANSWERED').count
    }
  end

  def campaigns_summary
    campaigns = @account.jabvox_dialer_campaigns
    range_campaigns = campaigns.where(created_at: @date_range.time_range)

    {
      active: campaigns.active.count,
      created: range_campaigns.count
    }
  end

  def whatsapp_summary
    batches = @account.jabvox_bulk_whatsapp_batches.where(created_at: @date_range.time_range)

    {
      batches: batches.count,
      sent: batches.sum(:sent_count_jabvox),
      failed: batches.sum(:failed_count_jabvox)
    }
  end

  def tickets_summary(daily)
    # El policy_scope de tickets puede traer tickets de OTRAS cuentas cuando el usuario
    # es staff/resolver del helpdesk central (ve bandejas de varias cuentas). El panel
    # es por cuenta: aquí SIEMPRE intersectamos con la cuenta actual para no contar
    # tickets ajenos (aislamiento por cuenta). El policy_scope sigue aplicando la
    # visibilidad por rol; este where solo acota a la cuenta del panel.
    scope = @ticket_scope.where(account_id: @account.id)
    tickets = scope.where(created_at: @date_range.time_range)
    open_tickets = scope.where(status_jabvox: JabvoxTicket::OPEN_STATUSES)

    daily[:tickets] = daily_counts(tickets, :created_at)

    {
      created: tickets.count,
      pending: open_tickets.count
    }
  end

  def events_summary(daily)
    events = @account.jabvox_calendar_events
                     .where(start_at: @date_range.time_range)
    daily[:events] = daily_counts(events, :start_at)

    {
      in_period: events.count,
      upcoming: @account.jabvox_calendar_events
                        .where(status: :pending)
                        .where('start_at >= ?', @date_range.now)
                        .count
    }
  end

  def tasks_summary
    tasks = @account.jabvox_tasks.active

    {
      created: tasks.where(created_at: @date_range.time_range).count,
      open: tasks.where(status_jabvox: 'open').count
    }
  end

  def kanban_summary
    placements = @account.jabvox_kanban_conversation_stages

    {
      active: placements.count,
      moved: placements.where(updated_at: @date_range.time_range).count
    }
  end

  def orders_summary
    orders = @account.jabvox_orders.where(created_at: @date_range.time_range)

    {
      created: orders.count,
      total: orders.sum(:total).to_f
    }
  end

  def sms_summary
    messages = @account.jabvox_sms_messages.where(created_at: @date_range.time_range)

    {
      sent: messages.where(status: 'sent').count,
      failed: messages.where(status: 'failed').count
    }
  end

  def email_summary
    logs = @account.jabvox_email_send_logs.where(created_at: @date_range.time_range)

    {
      sent: logs.where(status: 'sent').count,
      failed: logs.where(status: 'failed').count
    }
  end

  def forms_summary
    {
      submissions: @account.jabvox_form_submissions
                           .where(created_at: @date_range.time_range)
                           .count
    }
  end

  def daily_counts(scope, column, local_date: false)
    table = scope.klass.arel_table.name
    date_expression = if local_date
                        "DATE(#{table}.#{column})"
                      else
                        zone = ActiveRecord::Base.connection.quote(@date_range.time_zone.name)
                        "DATE(#{table}.#{column} AT TIME ZONE #{zone})"
                      end

    scope.unscope(:order).group(Arel.sql(date_expression)).count.transform_keys(&:to_date)
  end
end
