# frozen_string_literal: true

# Tareas de mantenimiento del módulo CDR.
# rubocop:disable Metrics/BlockLength
namespace :jabvox do
  namespace :cdr do
    # Re-enriquece registros YA materializados en jabvox_cdr_records aplicando de
    # nuevo el CdrLabelResolver sobre las columnas crudas guardadas (channel,
    # dstchannel, src, dst, uniqueid, linkedid). Corrige registros que quedaron con
    # origen/destino/medio incorrectos ('s' / 'manual') porque cuando se
    # sincronizaron no matcheaban (p. ej. llamadas ENTRANTES del trunk, o el dialer
    # cuyo call log llegó después). El sync normal ya no los vuelve a tocar (están
    # detrás del cursor), por eso esta tarea existe.
    #
    # Uso:
    #   rake jabvox:cdr:reenrich                 # todas las cuentas, solo registros dudosos
    #   ACCOUNT_ID=37 rake jabvox:cdr:reenrich   # una cuenta
    #   ALL=1 rake jabvox:cdr:reenrich           # re-enriquece TODOS los registros
    #   DRY_RUN=1 rake jabvox:cdr:reenrich       # no escribe, solo reporta
    desc 'Re-enriquece registros CDR locales (corrige entrantes/dialer mal resueltos)'
    task reenrich: :environment do
      account_id = ENV['ACCOUNT_ID'].presence
      all_records = ENV['ALL'] == '1'
      dry_run = ENV['DRY_RUN'] == '1'
      batch_size = (ENV['BATCH'].presence || 500).to_i

      accounts = account_id ? Account.where(id: account_id) : Account.joins(:jabvox_cdr_config).distinct
      total_updated = 0
      total_seen = 0

      accounts.find_each do |account|
        resolver = Jabvox::CdrLabelResolver.new(account)
        scope = JabvoxCdrRecord.for_account(account.id)
        # Por defecto solo los "dudosos": medio manual o destino/origen placeholder.
        scope = scope.where("medium = 'manual' OR dst IN ('s','0000') OR destination IN ('s','0000') OR destination IS NULL") unless all_records

        updated_here = 0
        seen_here = 0
        scope.find_in_batches(batch_size: batch_size) do |batch|
          # El resolver trabaja sobre "rows" con claves string (mismo shape del CDR).
          rows = batch.map { |rec| cdr_row_from(rec) }
          lookup = resolver.enrichment_for_rows(rows)

          batch.each_with_index do |rec, i|
            seen_here += 1
            row = rows[i]
            info = resolver.enrichment_for_row_with_inbound(row, lookup)
            attrs = reenriched_attrs(resolver, row, info)
            next if attrs.all? { |k, v| rec[k].to_s == v.to_s } # sin cambios reales

            updated_here += 1
            rec.update_columns(attrs) unless dry_run # rubocop:disable Rails/SkipsModelValidations
          end
        end

        total_updated += updated_here
        total_seen += seen_here
        Rails.logger.info "[cdr:reenrich] cuenta=#{account.id} vistos=#{seen_here} actualizados=#{updated_here}#{' (dry-run)' if dry_run}"
        puts "cuenta=#{account.id} vistos=#{seen_here} actualizados=#{updated_here}#{' (dry-run)' if dry_run}"
      end

      puts "TOTAL vistos=#{total_seen} actualizados=#{total_updated}#{' (dry-run)' if dry_run}"
    end

    # Reconstruye el hash "row" que espera el resolver desde el registro local.
    def cdr_row_from(rec)
      {
        'uniqueid' => rec.uniqueid,
        'linkedid' => rec.linkedid,
        'calldate' => rec.calldate,
        'src' => rec.src,
        'dst' => rec.dst,
        'channel' => rec.channel,
        'dstchannel' => rec.dstchannel
      }
    end

    # Atributos re-derivados que la tarea escribe (mismo criterio que el sync).
    def reenriched_attrs(resolver, row, info)
      {
        origin: resolver.origin_for(row, info),
        destination: resolver.destination_for(row, info),
        origin_channel: resolver.agent_channel_label(row, info),
        agent_extension: resolver.agent_extension_from_row(row),
        medium: info&.dig(:medium) || 'manual',
        agent_name: info&.dig(:agent_name),
        typification_id: info&.dig(:typification_id),
        typification: info&.dig(:typification)
      }
    end
  end
end
# rubocop:enable Metrics/BlockLength
