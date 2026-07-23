# Extra columns computed for a record that don't exist on its own table, so an
# external CRM can join activity straight to the lead/contact.
#
# Core Chatwoot models (Conversation, Message) don't carry a jabvox_lead_id, and
# messages don't even carry a contact_id — both are reachable only through the
# conversation. We materialize those links as real columns on the mirror tables:
#
#   conversations : jabvox_lead_id  (from the conversation's contact)
#   messages      : contact_id, jabvox_lead_id, conversation_display_id
#                   (from the message's conversation)
#
# The dialer call log stores its agent as agent_id_jabvox and reaches the lead
# only through the campaign contact, so we surface jabvox_lead_id there too.
#
# The contact -> lead lookup can be resolved either one-off (real-time mirror of a
# single row) or through a preloaded {contact_id => lead_id} map (backfill, to
# avoid a query per row). Pass a LeadResolver to reuse a map.
class Jabvox::ExternalExport::DerivedColumns
  # Column definitions per model name, for the schema builder. [{ name:, type: }].
  DEFS = {
    'Conversation' => [{ name: 'jabvox_lead_id', type: :integer }],
    'Message' => [
      { name: 'contact_id', type: :integer },
      { name: 'jabvox_lead_id', type: :integer },
      { name: 'conversation_display_id', type: :integer }
    ],
    # Contact notes (where a management activity can be recorded): link to the lead.
    'Note' => [
      { name: 'jabvox_lead_id', type: :integer }
    ],
    'JabvoxDialerCallLog' => [
      { name: 'contact_id', type: :integer },
      { name: 'jabvox_lead_id', type: :integer }
    ],
    # CDR of calls (from the PBX). It only carries agent_extension/agent_name and
    # uniqueid — no lead/contact link. We resolve lead/contact by matching uniqueid
    # against the call logs that DO carry them (click-to-call/manual via
    # JabvoxCallLog, dialer via JabvoxDialerCallLog -> campaign contact), so the CRM
    # can join the call recording straight to the lead.
    'JabvoxCdrRecord' => [
      { name: 'contact_id', type: :integer },
      { name: 'jabvox_lead_id', type: :integer }
    ],
    # Multi-row custom tables reach the account through their custom table; surface
    # account_id so the mirror table is filterable/relatable like the rest.
    'JabvoxCustomTableRow' => [
      { name: 'account_id', type: :integer }
    ],
    # Custom-column definitions also reach the account through their custom table.
    # Surface account_id so the schema of the multi-row tables is filterable and
    # joinable (jabvox_custom_table_id already travels as its own column, linking
    # each column definition to its table and, transitively, to its rows).
    'JabvoxCustomColumn' => [
      { name: 'account_id', type: :integer }
    ],
    # Users reach the account through account_users; surface account_id + the
    # account-scoped role so the CRM knows which agent belongs to the account.
    'User' => [
      { name: 'account_id', type: :integer },
      { name: 'role_jabvox', type: :string }
    ]
  }.freeze

  # LeadResolver (contact/uniqueid -> lead/contact) lives in its own file:
  # app/services/jabvox/external_export/lead_resolver.rb

  def self.defs_for(model)
    # base_class so STI subclasses (SuperAdmin < User) resolve to the parent defs.
    key = model.respond_to?(:base_class) ? model.base_class.name : model.name
    DEFS[key] || []
  end

  def initialize(resolver)
    @resolver = resolver
  end

  # [class, handler] pairs. Ordered list (not a hash keyed by class) so STI
  # subclasses match via is_a? — e.g. SuperAdmin < User resolves to :user_values.
  HANDLERS = [
    [Conversation, :conversation_values],
    [Message, :message_values],
    [JabvoxDialerCallLog, :dialer_call_values],
    [JabvoxCustomTableRow, :custom_table_row_values],
    [JabvoxCustomColumn, :custom_column_values],
    [User, :user_values],
    [Note, :note_values],
    [JabvoxCdrRecord, :cdr_record_values]
  ].freeze

  def for(record)
    pair = HANDLERS.find { |klass, _| record.is_a?(klass) }
    pair ? send(pair.last, record) : {}
  end

  private

  def conversation_values(conv)
    { 'jabvox_lead_id' => @resolver.lead_id_for(conv.contact_id) }
  end

  def message_values(msg)
    conv = msg.conversation
    contact_id = conv&.contact_id
    {
      'contact_id' => contact_id,
      'jabvox_lead_id' => @resolver.lead_id_for(contact_id),
      'conversation_display_id' => conv&.display_id
    }
  end

  def dialer_call_values(log)
    contact_id = log.jabvox_dialer_campaign_contact&.contact_id
    {
      'contact_id' => contact_id,
      'jabvox_lead_id' => @resolver.lead_id_for(contact_id)
    }
  end

  def custom_table_row_values(row)
    { 'account_id' => row.jabvox_custom_table&.account_id }
  end

  def custom_column_values(col)
    { 'account_id' => col.jabvox_custom_table&.account_id }
  end

  def note_values(note)
    { 'jabvox_lead_id' => @resolver.lead_id_for(note.contact_id) }
  end

  # CDR only has uniqueid; resolve lead/contact by matching it against the call
  # logs that carry the link (see LeadResolver#cdr_link_for).
  def cdr_record_values(cdr)
    lead_id, contact_id = @resolver.cdr_link_for(cdr.uniqueid)
    { 'jabvox_lead_id' => lead_id, 'contact_id' => contact_id }
  end

  # A user's account-scoped membership: the account_id we're exporting for and
  # their role in it. Read from account_users (a user may be in many accounts).
  def user_values(user)
    account_id = @resolver.account_id
    au = AccountUser.find_by(user_id: user.id, account_id: account_id)
    { 'account_id' => account_id, 'role_jabvox' => au&.role }
  end
end
