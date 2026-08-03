# Counts call typifications per lead for the leads list.
#
# A "tipificación de llamada" is the outcome an agent marks when ending a call. It
# lives as typification_id on:
#   - JabvoxCallLog (click-to-call / manual): carries jabvox_lead_id directly.
#   - JabvoxDialerCallLog (dialer): reaches the lead through the campaign contact,
#     so it's counted per contact_id and mapped back to the lead.
#
# Counts are computed with grouped queries over the whole batch (no N+1) and
# returned keyed by lead id, so the list can show a per-lead column.
class Jabvox::LeadTypificationCountsService
  # leads: the page of JabvoxLead records being rendered.
  def initialize(account, leads)
    @account = account
    @leads = leads.to_a
    @lead_ids = @leads.map(&:id)
    @contact_ids = @leads.filter_map(&:contact_id).uniq
  end

  # { lead_id => count }. Sums click-to-call/manual (by lead) + dialer (by contact).
  def by_lead
    return {} if @lead_ids.empty?

    counts = Hash.new(0)
    direct_counts.each { |lead_id, n| counts[lead_id.to_i] += n.to_i }
    dialer_counts_by_contact.each do |contact_id, n|
      lead_id = lead_id_for_contact[contact_id.to_i]
      counts[lead_id] += n.to_i if lead_id
    end
    counts
  end

  private

  # Click-to-call / manual calls with a typification, grouped by lead.
  def direct_counts
    @account.jabvox_call_logs
            .where(jabvox_lead_id: @lead_ids)
            .where.not(typification_id: nil)
            .group(:jabvox_lead_id).count
  end

  # Dialer calls with a typification reach the contact through the campaign contact;
  # count per contact_id, then map to the lead.
  def dialer_counts_by_contact
    return {} if @contact_ids.empty?

    @account.jabvox_dialer_call_logs
            .where.not(typification_id: nil)
            .joins(:jabvox_dialer_campaign_contact)
            .where(jabvox_dialer_campaign_contacts: { contact_id: @contact_ids })
            .group('jabvox_dialer_campaign_contacts.contact_id').count
  end

  def lead_id_for_contact
    @lead_id_for_contact ||= @leads.each_with_object({}) do |lead, h|
      h[lead.contact_id] = lead.id if lead.contact_id
    end
  end
end
