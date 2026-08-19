# frozen_string_literal: true

# Registrador de eventos del softphone. Escribe en la tabla (para el panel/historial) y en
# un archivo de log dedicado (log/jabvox_softphone.log) para diagnóstico técnico.
#
# ROBUSTEZ: nada de lo que hace aquí puede tumbar una llamada. Todo va envuelto en rescue;
# si el logging falla, se registra el fallo del logging y se sigue. El softphone es
# independiente: un error de una cuenta/llamada no afecta a las demás.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Softphone
    class CallLogger
      def self.file_logger
        @file_logger ||= ActiveSupport::Logger.new(
          Rails.root.join('log/jabvox_softphone.log'), 3, 5.megabytes
        )
      end

      def initialize(call_log)
        @call_log = call_log
      end

      # Registra un evento de la llamada (tabla + archivo). Nunca levanta.
      def event(type, detail: nil, occurred_at: Time.current)
        @call_log.jabvox_softphone_call_events.create!(
          account_id: @call_log.account_id,
          event_type: type, detail: detail.to_s.presence, occurred_at: occurred_at
        )
        write_file("event=#{type} detail=#{detail}")
      rescue StandardError => e
        write_file("logging_error=#{e.class} #{e.message}")
      end

      # Traza a archivo una línea estructurada con el contexto de la llamada.
      def write_file(line)
        self.class.file_logger.info(
          "[softphone] account=#{@call_log.account_id} call=#{@call_log.id} " \
          "ext=#{@call_log.extension} to=#{@call_log.phone_number} " \
          "dir=#{@call_log.direction} #{line}"
        )
      rescue StandardError
        # el archivo de log jamás debe romper el flujo de la llamada
        nil
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
