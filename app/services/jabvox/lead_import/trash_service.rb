# Moves leads imported by a source to the trash (snapshot + destroy) and restores
# them. A snapshot captures the lead, its contact, and its custom-field row so a
# restore can recreate everything. Restores are best-effort per lead and isolated.
class Jabvox::LeadImport::TrashService
  def initialize(account)
    @account = account
  end

  # Snapshots and deletes every lead linked to the given source. Returns the count.
  def trash_source_leads(source, deleted_by: nil)
    count = 0
    source.records.includes(jabvox_lead: :contact).find_each do |record|
      lead = record.jabvox_lead
      next unless lead

      trash_lead(lead, source_name: source.name_jabvox,
                       external_id: record.external_id_jabvox, deleted_by: deleted_by)
      count += 1
    end
    count
  end

  # Snapshots and deletes the given leads (any deletion path — e.g. manual bulk
  # delete). Each lead goes to the restorable trash instead of being lost. Returns
  # the count actually trashed. `origin` is a short label shown in the trash.
  def trash_leads(leads, origin: nil, deleted_by: nil)
    count = 0
    Array(leads).each do |lead|
      next unless lead

      ext = lead.jabvox_lead_source_records.first&.external_id_jabvox
      trash_lead(lead, source_name: origin, external_id: ext, deleted_by: deleted_by)
      count += 1
    end
    count
  end

  # Only snapshots the given leads to the trash WITHOUT deleting them (the caller
  # deletes afterwards, e.g. a bulk delete_all). Idempotent per lead per run.
  def snapshot_leads(leads, origin: nil, deleted_by: nil)
    Array(leads).each do |lead|
      next unless lead

      ext = lead.jabvox_lead_source_records.first&.external_id_jabvox
      @account.jabvox_deleted_leads.create!(
        original_lead_id_jabvox: lead.id, source_name_jabvox: origin,
        external_id_jabvox: ext, deleted_by: deleted_by, deleted_at_jabvox: Time.current,
        snapshot_jabvox: {
          'lead' => { 'lead_number' => lead.lead_number },
          'contact' => contact_snapshot(lead.contact),
          'custom_fields' => custom_fields_for(lead)
        }
      )
    end
  end

  # Restores one trashed lead from its snapshot (super-admin action).
  def restore(deleted_lead)
    return false unless deleted_lead.restorable?

    snap = deleted_lead.snapshot_jabvox || {}
    ActiveRecord::Base.transaction do
      contact = restore_contact(snap['contact'] || {})
      lead = @account.jabvox_leads.find_or_create_by!(contact: contact)
      restore_custom_fields(lead, snap['custom_fields'] || {})
      deleted_lead.update!(restored_at_jabvox: Time.current)
    end
    true
  rescue StandardError => e
    Rails.logger.error("[LeadImport::Trash] restore ##{deleted_lead.id} #{e.class}: #{e.message}")
    false
  end

  private

  def trash_lead(lead, source_name:, external_id:, deleted_by:)
    contact = lead.contact
    custom = custom_fields_for(lead)
    @account.jabvox_deleted_leads.create!(
      original_lead_id_jabvox: lead.id,
      source_name_jabvox: source_name,
      external_id_jabvox: external_id,
      deleted_by: deleted_by,
      deleted_at_jabvox: Time.current,
      snapshot_jabvox: {
        'lead' => { 'lead_number' => lead.lead_number },
        'contact' => contact_snapshot(contact),
        'custom_fields' => custom
      }
    )
    # Destroying the lead cascades its source records and custom rows.
    lead.destroy!
  end

  def contact_snapshot(contact)
    return {} unless contact

    {
      'name' => contact.name, 'last_name' => contact.last_name,
      'email' => contact.email, 'phone_number' => contact.phone_number,
      'additional_attributes' => contact.additional_attributes,
      'custom_attributes' => contact.custom_attributes
    }
  end

  def custom_fields_for(lead)
    table = @account.jabvox_custom_tables.find_by(linked_to_jabvox: 'leads')
    return {} unless table

    lead.jabvox_custom_table_rows.find_by(jabvox_custom_table: table)&.data_jabvox || {}
  end

  def restore_contact(data)
    phone = data['phone_number']
    contact = (phone.present? && @account.contacts.find_by(phone_number: phone)) ||
              @account.contacts.new(contact_type: :lead)
    contact.name = data['name'] if data['name'].present?
    contact.last_name = data['last_name'] if data['last_name'].present?
    contact.phone_number = phone if phone.present?
    contact.email = data['email'] if data['email'].present?
    contact.additional_attributes = data['additional_attributes'] || contact.additional_attributes || {}
    contact.custom_attributes = data['custom_attributes'] || contact.custom_attributes || {}
    contact.save!(validate: false)
    contact
  end

  def restore_custom_fields(lead, custom)
    return if custom.blank?

    table = @account.jabvox_custom_tables.find_by(linked_to_jabvox: 'leads')
    return unless table

    row = lead.jabvox_custom_table_rows.find_or_initialize_by(jabvox_custom_table: table)
    row.data_jabvox = (row.data_jabvox || {}).merge(custom)
    row.save!
  end
end
