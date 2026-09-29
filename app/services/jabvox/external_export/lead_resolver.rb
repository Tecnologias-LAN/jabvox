# Resuelve los enlaces que algunas filas exportadas necesitan pero no llevan en su propia
# tabla:
#
# - contact_id -> lead_id (para conversaciones, mensajes, notas y llamadas del marcador).
#
# - uniqueid   -> [lead_id, contact_id] para las filas de CDR, cruzadas contra los registros
#   de llamada que SÍ llevan el enlace (JabvoxCallLog para click-to-call/manual, y
#   JabvoxDialerCallLog -> contacto de campaña para el marcador).
#
# Tras retirar Leads, `lead_id` ES el id del contacto: la columna se conserva en el esquema
# exportado porque ya existe en las bases de datos de los clientes y sus consultas la usan.
# Quitarla rompería esas integraciones; dejarla vacía perdería el enlace.
class Jabvox::ExternalExport::LeadResolver
  attr_reader :account_id

  def initialize(account_id, map: nil)
    @account_id = account_id
    @map = map
  end

  # Ya no hace falta precargar mapa alguno: lead_id y contact_id son el mismo valor. Se
  # conserva la firma para no tocar a quien la llama.
  def self.preloaded(account_id)
    new(account_id)
  end

  def lead_id_for(contact_id)
    return nil if contact_id.blank?

    contact_id
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
    # click-to-call / manual: JabvoxCallLog lleva uniqueid + contacto directamente.
    JabvoxCallLog.where(account_id: @account_id)
                 .where.not(uniqueid: [nil, ''])
                 .pluck(:uniqueid, :contact_id)
                 .each { |uid, contact| map[uid] ||= [contact, contact] }
    # marcador: JabvoxDialerCallLog lleva uniqueid_jabvox; el contacto, vía contacto de campaña.
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
