# frozen_string_literal: true

# jabvox.lead.sync_contacts — crea el lead que falte para cada contacto de la
# cuenta. Inserción por lotes (nada de N+1) e idempotente ante una carrera.
class Jabvox::Flows::Nodes::Jabvox::LeadSyncContactsNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.lead.sync_contacts'
  label 'Sincronizar contactos → leads'

  BATCH_SIZE = 1000

  def perform
    existing = JabvoxLead.where(account_id: account.id).select(:contact_id)
    missing_ids = account.contacts.where.not(id: existing).pluck(:id)
    return { 'synced' => 0, 'pending' => 0 } if missing_ids.empty?

    { 'synced' => insert_missing_leads(missing_ids), 'pending' => missing_ids.length }
  end

  private

  # unique_by (account_id, contact_id) hace la inserción idempotente: si otro
  # proceso ya creó el lead, la fila se descarta en vez de reventar.
  def insert_missing_leads(missing_ids)
    next_number = (JabvoxLead.where(account_id: account.id).maximum(:lead_number) || 0) + 1
    now = Time.current
    missing_ids.each_slice(BATCH_SIZE).sum do |slice|
      rows = slice.map do |contact_id|
        { account_id: account.id, contact_id: contact_id, lead_number: next_number,
          custom_fields_jabvox: {}, created_at: now, updated_at: now }.tap { next_number += 1 }
      end
      JabvoxLead.insert_all(rows, unique_by: %i[account_id contact_id]).rows.size # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
