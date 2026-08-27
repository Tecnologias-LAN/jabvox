# frozen_string_literal: true

require 'socket'
require 'timeout'

# Consulta rápida al PBX (AMI) para saber qué extensiones PJSIP están registradas/online.
# Usa la config VoIP de la cuenta (host/puerto/credenciales AMI). Timeout corto: si el PBX
# no responde, devuelve nil y el panel muestra "PBX no disponible" en vez de colgarse.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  module Softphone
    class AmiEndpointsProbe
      AMI_TIMEOUT = 5

      def initialize(voip_config)
        @config = voip_config
      end

      # Consulta el estado de los contactos PJSIP. Devuelve un hash con el resultado o un
      # error clasificado (para mostrar el motivo exacto en el panel):
      #   { ok: true,  contacts: { "1001" => "reachable", "1002" => "unreachable", ... } }
      #   { ok: false, error_code: 'timeout'|'connection_refused'|'login_failed'|'ami_error',
      #                error: '<mensaje>' }
      def probe
        with_ami do |socket|
          send_action(socket, 'PJSIPShowContacts')
          { ok: true, contacts: parse_contacts(read_event_list(socket)) }
        end
      rescue Timeout::Error
        { ok: false, error_code: 'timeout', error: 'El PBX no respondió a tiempo.' }
      rescue Errno::ECONNREFUSED
        { ok: false, error_code: 'connection_refused', error: 'Conexión rechazada por el PBX.' }
      rescue SocketError => e
        { ok: false, error_code: 'host_unresolved', error: "No se resolvió el host: #{e.message}" }
      rescue AmiLoginError => e
        { ok: false, error_code: 'login_failed', error: e.message }
      rescue StandardError => e
        { ok: false, error_code: 'ami_error', error: e.message }
      end

      private

      def with_ami
        Timeout.timeout(AMI_TIMEOUT) do
          socket = TCPSocket.new(@config.host, @config.port.to_i)
          socket.gets # banner
          send_action(socket, 'Login', username: @config.username, secret: @config.password, events: 'off')
          resp = read_response(socket)
          unless resp['response']&.casecmp('success')&.zero?
            raise AmiLoginError, "Login AMI rechazado: #{resp['message'] || 'credenciales inválidas'}"
          end

          result = yield socket
          socket.close
          result
        end
      end

      def send_action(socket, action, **params)
        msg = "Action: #{action}\r\n"
        params.each { |k, v| msg << "#{k}: #{v}\r\n" }
        msg << "\r\n"
        socket.write(msg)
      end

      def read_response(socket)
        result = {}
        loop do
          line = socket.gets&.chomp
          break if line.blank?

          key, val = line.split(': ', 2)
          result[key.to_s.downcase] = val if key
        end
        result
      end

      # Lee eventos hasta el evento de fin de lista (ContactList/EndpointList complete).
      def read_event_list(socket)
        events = []
        current = {}
        loop do
          line = socket.gets
          break if line.nil?

          line = line.chomp
          if line.empty?
            events << current unless current.empty?
            current = {}
          else
            key, val = line.split(': ', 2)
            current[key.to_s.downcase] = val if key
            break if val.to_s.include?('Complete') || key.to_s.include?('Complete')
          end
        end
        events
      end

      # Mapa extensión => estado del contacto ("reachable"/"unreachable"/"unknown"). Las
      # extensiones sin contacto (no registradas) no aparecen aquí.
      def parse_contacts(events)
        events.each_with_object({}) do |ev, acc|
          ext = (ev['aor'] || ev['endpointname'] || ev['objectname']).to_s[/\d+/]
          next if ext.blank?

          acc[ext] = ev['status'].to_s.downcase.presence || 'unknown'
        end
      end
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
