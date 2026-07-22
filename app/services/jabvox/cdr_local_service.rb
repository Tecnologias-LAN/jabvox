# frozen_string_literal: true

# Lee el CDR desde la tabla LOCAL jabvox_cdr_records (materializada + enriquecida
# por CdrSyncService). Devuelve EXACTAMENTE el mismo contrato que
# CdrMysqlService#records/#summary, para que el reporte y el frontend no cambien.
#
# Ventaja: al ser una sola tabla local con los datos ya resueltos (número real,
# medio, tipificación, agente), los filtros y el COUNT/paginación son exactos a
# cualquier volumen — incluidos los filtros que antes no eran posibles (medio,
# tipificación, origen/destino por número real que en el CDR crudo era 's').
module Jabvox
  class CdrLocalService
    def initialize(account)
      @account = account
    end

    # { records: [...], total: N } con el mismo shape que el servicio MySQL.
    def records(filters = {}, page: 1, per_page: 50)
      page = [page.to_i, 1].max
      per_page = per_page.to_i.clamp(1, 200)

      rel = filtered(filters)
      total = rel.count
      rows = rel.order(calldate: :desc).limit(per_page).offset((page - 1) * per_page)
      { records: rows.map { |r| normalize(r) }, total: total }
    rescue StandardError => e
      Rails.logger.error "[CdrLocal] records failed: #{e.message}"
      { records: [], total: 0, error: e.message }
    end

    # { summary: [...] } agrupado por extensión de agente, igual que el MySQL.
    def summary(filters = {})
      rel = filtered(filters).where.not(agent_extension: [nil, ''])
      # Una sola query agrupada por agente: cuenta por disposición con SUM(CASE)
      # y el tiempo hablado. Evita encadenar .where sobre la relación agrupada
      # (que la mutaba y devolvía resultados vacíos/incorrectos).
      grouped = rel.group(:agent_extension).pluck(
        Arel.sql('agent_extension'),
        Arel.sql('COUNT(*)'),
        Arel.sql("SUM(CASE WHEN disposition = 'ANSWERED'  THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN disposition = 'NO ANSWER' THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN disposition = 'BUSY'      THEN 1 ELSE 0 END)"),
        Arel.sql("SUM(CASE WHEN disposition = 'FAILED'    THEN 1 ELSE 0 END)"),
        Arel.sql('COALESCE(SUM(billsec), 0)')
      )
      rows = grouped.map { |cols| build_summary_row(cols) }
      { summary: rows.sort_by { |r| -r[:total] } }
    rescue StandardError => e
      Rails.logger.error "[CdrLocal] summary failed: #{e.message}"
      { summary: [], error: e.message }
    end

    # Nombre de la grabación por uniqueid (para la descarga SSH del recording).
    def recording_file(uniqueid)
      JabvoxCdrRecord.for_account(@account.id).where(uniqueid: uniqueid).pick(:recordingfile)
    end

    private

    # Reutiliza el resolver (fuente de verdad extensión→agente, ya probado) en vez
    # de una join propia; el resolver mapea la extensión al nombre/id del usuario.
    def resolver
      @resolver ||= Jabvox::CdrLabelResolver.new(@account)
    end

    # cols = [ext, total, answered, no_answer, busy, failed, talk] (del pluck agrupado)
    def build_summary_row(cols)
      ext, total, answered, no_answer, busy, failed, talk = cols
      total = total.to_i
      answered = answered.to_i
      {
        agent: resolver.user_name_for(ext) || ext,
        agent_extension: ext,
        user_id: resolver.user_id_for(ext),
        total: total,
        answered: answered,
        no_answer: no_answer.to_i,
        busy: busy.to_i,
        failed: failed.to_i,
        talk_seconds: talk.to_i,
        answer_rate: total.zero? ? 0 : ((answered.to_f / total) * 100).round(1)
      }
    end

    def filtered(filters) # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity, Metrics/MethodLength
      rel = JabvoxCdrRecord.for_account(@account.id)
      rel = rel.where('calldate >= ?', filters[:from]) if filters[:from].present?
      rel = rel.where('calldate <= ?', filters[:to]) if filters[:to].present?

      if filters[:extension].present?
        ext = filters[:extension].to_s
        # Agente en cualquier leg + origen/destino crudo (paridad con el MySQL).
        rel = rel.where(
          'agent_extension = :e OR src = :e OR dst = :e OR channel LIKE :sip OR ' \
          'channel LIKE :pjsip OR dstchannel LIKE :sip OR dstchannel LIKE :pjsip',
          e: ext, sip: "SIP/#{ext}-%", pjsip: "PJSIP/#{ext}-%"
        )
      end
      if filters[:ext_from].present?
        rel = rel.where("agent_extension REGEXP '^[0-9]+$' AND CAST(agent_extension AS UNSIGNED) >= ?",
                        filters[:ext_from].to_s.gsub(/\D/, '').to_i)
      end
      if filters[:ext_to].present?
        rel = rel.where("agent_extension REGEXP '^[0-9]+$' AND CAST(agent_extension AS UNSIGNED) <= ?",
                        filters[:ext_to].to_s.gsub(/\D/, '').to_i)
      end
      # origen/destino por NÚMERO REAL (columnas enriquecidas), no el crudo 's'.
      rel = rel.where('origin LIKE ?', "%#{sanitize_like(filters[:src])}%") if filters[:src].present?
      rel = rel.where('destination LIKE ?', "%#{sanitize_like(filters[:dst])}%") if filters[:dst].present?
      rel = rel.where(disposition: filters[:disposition]) if valid_disposition?(filters[:disposition])
      rel = rel.where(medium: filters[:medium]) if JabvoxCdrRecord::MEDIUMS.include?(filters[:medium])
      rel = rel.where(typification_id: filters[:typification_id]) if filters[:typification_id].present?
      rel
    end

    def valid_disposition?(value)
      JabvoxCdrRecord::DISPOSITIONS.include?(value)
    end

    def sanitize_like(value)
      value.to_s.gsub(/[%_\\]/) { |c| "\\#{c}" }
    end

    # MISMO shape que CdrMysqlService#normalize, pero leyendo columnas ya resueltas.
    def normalize(rec)
      {
        uniqueid: rec.uniqueid,
        calldate: rec.calldate,
        src: rec.src,
        dst: rec.dst,
        origin: rec.origin,
        destination: rec.destination,
        origin_channel: rec.origin_channel,
        agent_extension: rec.agent_extension,
        dst_channel: rec.dstchannel.presence,
        medium: rec.medium.presence || 'manual',
        agent_name: rec.agent_name,
        disposition: rec.disposition,
        duration: rec.duration.to_i,
        billsec: rec.billsec.to_i,
        recording_file: rec.recordingfile.presence,
        typification: rec.typification,
        typification_id: rec.typification_id
      }
    end
  end
end
