# Loads management activity (gestiones) for a set of contacts, for the leads list.
#
# A "gestión" is a private Message (or a Note, for leads without a conversation)
# whose content_attributes carry a jabvox_management_state_id. That id — NOT the
# embedded state name — is what makes it a gestión (a plain private note is only
# text, with no state id, and must never be counted here). The state name is read
# from the embedded snapshot and, if that came empty, resolved from the
# JabvoxManagementState record by id, so no gestión is dropped for a blank name.
# Each gestión records the state applied, the medium it was done through
# (jabvox_call_source: dialer / click_to_call / lead_detail / conversations /
# kanban) and who did it.
#
# This service returns, per contact:
#   - all managements within an optional date range (the historic view), each with
#     its state, medium, timestamp and agent — NOT just the latest one.
#   - the latest management (state + medium) for the list's summary columns.
#   - a management count.
#
# Everything is loaded with grouped queries over the whole contact batch (no N+1),
# and both messages AND notes are considered so leads without a conversation don't
# lose their gestiones.
class Jabvox::LeadManagementsService
  # A single management row surfaced to the UI.
  Management = Struct.new(:state, :source, :at, :agent_name, :origin, keyword_init: true)

  def initialize(account, contact_ids, date_from: nil, date_to: nil)
    @account = account
    @contact_ids = Array(contact_ids).map(&:to_i).uniq.reject(&:zero?)
    @from = date_from
    @to = date_to
  end

  # { contact_id => [Management, ...] } ordered newest-first, within the range.
  def by_contact
    return {} if @contact_ids.empty?

    grouped = Hash.new { |h, k| h[k] = [] }
    (message_rows + note_rows).each do |row|
      cid = row[:contact_id]
      next unless cid

      grouped[cid] << Management.new(
        state: row[:state], source: row[:source], at: row[:at],
        agent_name: row[:agent_name], origin: row[:origin]
      )
    end
    grouped.each_value { |list| list.sort_by! { |m| m.at.to_s }.reverse! }
    grouped
  end

  # { contact_id => count } of managements in range (for the per-lead column).
  def counts_by_contact
    by_contact.transform_values(&:size)
  end

  # Total managements across the whole batch/range (for the global summary).
  def total
    by_contact.values.sum(&:size)
  end

  private

  # Gestiones stored as private messages, reached through the conversation's contact.
  def message_rows
    scope = @account.messages.where(private: true)
                    .joins('JOIN conversations ON conversations.id = messages.conversation_id')
                    .where(conversations: { contact_id: @contact_ids })
                    .where(state_id_present_sql('messages'))
    scope = with_range(scope, 'messages').reorder(nil)
    scope.pluck(
      Arel.sql('conversations.contact_id'),
      Arel.sql(state_id_select_sql('messages')),
      Arel.sql(state_select_sql('messages')),
      Arel.sql(source_select_sql('messages')),
      Arel.sql('messages.created_at'),
      Arel.sql('messages.sender_id'),
      Arel.sql('messages.sender_type')
    ).map do |row|
      cid, state_id, state, source, at, sender_id, sender_type = row
      { contact_id: cid.to_i, state: resolve_state_name(state, state_id), source: source, at: at,
        agent_name: agent_name_for(sender_id, sender_type), origin: 'message' }
    end
  end

  # Gestiones stored as contact notes (leads with no conversation), linked to the
  # lead through the note's contact.
  def note_rows
    return [] unless Note.column_names.include?('contact_id')

    scope = @account.notes.where(contact_id: @contact_ids)
                    .where(state_id_present_sql('notes'))
    scope = with_range(scope, 'notes').reorder(nil)
    scope.pluck(
      Arel.sql('notes.contact_id'),
      Arel.sql(state_id_select_sql('notes')),
      Arel.sql(state_select_sql('notes')),
      Arel.sql(source_select_sql('notes')),
      Arel.sql('notes.created_at')
    ).map do |cid, state_id, state, source, at|
      { contact_id: cid.to_i, state: resolve_state_name(state, state_id), source: source, at: at,
        agent_name: nil, origin: 'note' }
    end
  end

  def with_range(scope, table)
    scope = scope.where("#{table}.created_at >= ?", @from.beginning_of_day) if @from
    scope = scope.where("#{table}.created_at <= ?", @to.end_of_day) if @to
    scope
  end

  # jsonb text-extraction reused across select/where. content_attributes is stored
  # as jsonb; (#>> '{}')::json->>'key' matches the existing patterns in the codebase.
  def state_select_sql(table)
    "(#{table}.content_attributes #>> '{}')::json->>'jabvox_management_state_name'"
  end

  def source_select_sql(table)
    "(#{table}.content_attributes #>> '{}')::json->>'jabvox_call_source'"
  end

  def state_id_select_sql(table)
    "(#{table}.content_attributes #>> '{}')::json->>'jabvox_management_state_id'"
  end

  # A row is a gestión when it carries a management STATE ID — that's what
  # distinguishes it from a plain private note (only text, no state id).
  def state_id_present_sql(table)
    "#{state_id_select_sql(table)} IS NOT NULL AND #{state_id_select_sql(table)} <> ''"
  end

  # The gestión's state name: prefer the embedded snapshot; if it came empty, fall
  # back to the live JabvoxManagementState name resolved by id. Never returns nil
  # for a real gestión as long as the state still exists.
  def resolve_state_name(embedded, state_id)
    return embedded if embedded.present?

    id = state_id.to_i
    return nil if id.zero?

    state_names[id]
  end

  # { state_id => name } for every state referenced by the batch (one query).
  def state_names
    @state_names ||= @account.jabvox_management_states.pluck(:id, :name_jabvox).to_h
  end

  # Resolves the agent name for a message sender. Cached per batch so we don't
  # query users once per row.
  def agent_name_for(sender_id, sender_type)
    return nil unless sender_type == 'User' && sender_id

    user_names[sender_id.to_i]
  end

  def user_names
    @user_names ||= begin
      ids = collect_sender_ids
      ids.empty? ? {} : User.where(id: ids).pluck(:id, :name).to_h
    end
  end

  # Sender ids referenced by the message gestiones (one query to name them all).
  # reorder(nil) drops Message's default scope ORDER BY, which Postgres rejects
  # alongside SELECT DISTINCT unless the ordered column is in the select list.
  def collect_sender_ids
    @account.messages.where(private: true)
            .joins('JOIN conversations ON conversations.id = messages.conversation_id')
            .where(conversations: { contact_id: @contact_ids })
            .where(state_id_present_sql('messages'))
            .where(sender_type: 'User')
            .then { |s| @from ? s.where('messages.created_at >= ?', @from.beginning_of_day) : s }
            .then { |s| @to ? s.where('messages.created_at <= ?', @to.end_of_day) : s }
            .reorder(nil).distinct.pluck(:sender_id).compact
  end
end
