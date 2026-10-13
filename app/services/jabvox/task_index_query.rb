# frozen_string_literal: true

# Builds the account-scoped list used by task boards, the calendar, and the task home.
class Jabvox::TaskIndexQuery
  class InvalidFilter < StandardError; end

  def initialize(scope:, params:)
    @scope = scope
    @params = params
  end

  def call
    tasks = @scope.includes(:board, :stage, :contact, :assignee, :assignees, :automations)
    tasks = apply_deleted_filter(tasks)
    tasks = tasks.where(board_id: @params[:board_id]) if @params[:board_id].present?
    tasks = apply_status_filter(tasks)
    tasks = tasks.where(contact_id: @params[:contact_id]) if @params[:contact_id].present?
    # `lead_id` remains an alias for contact_id for links and older callers.
    tasks = tasks.where(contact_id: @params[:lead_id]) if @params[:lead_id].present?
    tasks = tasks.where(due_at_jabvox: @params[:from]..) if @params[:from].present?
    tasks = tasks.where(due_at_jabvox: ..@params[:to]) if @params[:to].present?
    tasks
  end

  private

  def apply_deleted_filter(tasks)
    deleted_filter = @params[:deleted]
    unless [nil, true, false, 'true', 'false'].include?(deleted_filter)
      raise InvalidFilter, 'Filtro de papelera no válido'
    end

    [true, 'true'].include?(deleted_filter) ? tasks.trashed : tasks.active
  end

  def apply_status_filter(tasks)
    status = @params[:status]
    return tasks unless status.present?
    raise InvalidFilter, 'Estado de tarea no válido' unless JabvoxTask::STATUSES.include?(status)

    tasks.where(status_jabvox: status)
  end
end
