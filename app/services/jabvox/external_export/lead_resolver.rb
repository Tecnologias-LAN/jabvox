# Resolves the lead/contact links that some exported rows need but don't carry
# on their own table:
#
# - contact_id -> lead_id (for conversations, messages, notes, dialer calls).
# - uniqueid   -> [lead_id, contact_id] for CDR rows, matched against the call
#   logs that DO carry the link (JabvoxCallLog for click-to-call/manual, and
#   JabvoxDialerCallLog -> campaign contact for the dialer).
#
# Without a preloaded map it queries per call (fine for the single-row real-time
# path); with one (backfill) it's a hash lookup. Both maps are built once and
# memoized.
class Jabvox::ExternalExport::LeadResolver
  attr_reader :account_id

  def initialize(account_id, map: nil)
    @account_id = account_id
    @map = map
  end

  # Preload the whole account's contact->lead map in one query (backfill path).
  def self.preloaded(account_id)
    map = JabvoxLead.where(account_id: account_id)
                    .where.not(contact_id: nil)
                    .pluck(:contact_id, :id)
                    .to_h
    new(account_id, map: map)
  end

  def lead_id_for(contact_id)
    return nil if contact_id.blank?
    return @map[contact_id] if @map

    JabvoxLead.where(account_id: @account_id, contact_id: contact_id).pick(:id)
  end

  # uniqueid -> [lead_id, contact_id] for CDR rows.
  def cdr_link_for(uniqueid)
    return [nil, nil] if uniqueid.blank?

    cdr_map[uniqueid] || [nil, nil]
  end

  def cdr_map
    @cdr_map ||= build_cdr_map
  end

  private

  def build_cdr_map
    map = {}
    # click-to-call / manual: JabvoxCallLog has uniqueid + lead + contact directly.
    JabvoxCallLog.where(account_id: @account_id)
                 .where.not(uniqueid: [nil, ''])
                 .pluck(:uniqueid, :jabvox_lead_id, :contact_id)
                 .each { |uid, lead, contact| map[uid] ||= [lead, contact] }
    # dialer: JabvoxDialerCallLog has uniqueid_jabvox; lead/contact via campaign contact.
    JabvoxDialerCallLog
      .where(account_id: @account_id)
      .where.not(uniqueid_jabvox: [nil, ''])
      .includes(:jabvox_dialer_campaign_contact)
      .find_each do |log|
        uid = log.uniqueid_jabvox
        next if uid.blank? || map.key?(uid)

        contact_id = log.jabvox_dialer_campaign_contact&.contact_id
        map[uid] = [lead_id_for(contact_id), contact_id]
      end
    map
  end
end
