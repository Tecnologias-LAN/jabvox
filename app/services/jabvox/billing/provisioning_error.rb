# frozen_string_literal: true

# Error de aprovisionamiento de billing. En archivo propio para que Zeitwerk lo
# resuelva desde el Job y el Service sin depender del orden de carga.
class Jabvox::Billing::ProvisioningError < StandardError; end
