# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::DashboardController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature :none
  include JabvoxPermissions

  def show
    range = Jabvox::DashboardDateRange.new(
      account: Current.account,
      date_from: params[:date_from],
      date_to: params[:date_to]
    )
    modules = visible_modules

    render json: Jabvox::DashboardSummaryService.new(
      account: Current.account,
      date_range: range,
      modules: modules,
      ticket_scope: modules.include?(:tickets) ? policy_scope(JabvoxTicket) : nil
    ).call
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def visible_modules
    enabled_modules = {
      calls: ['jabvox_cdr', %w[jabvox_cdr_view_reports jabvox_cdr_manage]],
      campaigns: ['jabvox_dialer', %w[jabvox_dialer_use jabvox_dialer_manage]],
      whatsapp: ['jabvox_bulk_whatsapp', %w[jabvox_bulk_whatsapp_send]],
      tickets: ['jabvox_tickets', nil],
      events: ['jabvox_calendar', %w[jabvox_calendar_manage]],
      tasks: ['jabvox_tasks', %w[jabvox_tasks_view_all jabvox_tasks_manage]],
      kanban: ['jabvox_kanban', %w[jabvox_kanban_view_all jabvox_kanban_manage]],
      orders: ['jabvox_products', %w[jabvox_products_manage jabvox_orders_manage]],
      sms: ['jabvox_sms', %w[jabvox_sms_view jabvox_sms_manage]],
      email: ['jabvox_email', %w[jabvox_email_manage]],
      forms: ['jabvox_forms', %w[jabvox_forms_manage]]
    }

    enabled_modules.filter_map do |key, config|
      key if module_visible?(key, *config)
    end
  end

  def module_visible?(key, feature, permissions)
    return false unless feature_enabled?(key, feature)
    return false if permissions&.none? { |permission| can_read_module?(permission) }
    return false if key == :tickets && !ticket_read_access?

    true
  end

  def feature_enabled?(key, feature)
    return calendar_enabled? if key == :events

    Current.account.feature_enabled?(feature)
  end

  def can_read_module?(permission)
    account_user = Current.account_user
    return true if account_user&.custom_role.nil? && !account_user&.administrator?

    jabvox_can?(permission)
  end

  def ticket_read_access?
    Current.user.present?
  end

  def calendar_enabled?
    Current.account.jabvox_calendar_enabled_jabvox? ||
      Current.account.jabvox_smtp_config.present?
  end
end
