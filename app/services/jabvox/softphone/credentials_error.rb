# frozen_string_literal: true

# Error del servicio de credenciales del softphone. Archivo propio para que Zeitwerk lo
# resuelva sin depender del orden de carga.
class Jabvox::Softphone::CredentialsError < StandardError; end
