# frozen_string_literal: true

# Cliente del HERMES PROVISIONADOR (instancia central del super admin). Jabvox NO crea
# contenedores ni toca OVH directamente: le PIDE al Hermes Provisionador —vía su MCP de
# infraestructura— que aprovisione/gestione la instancia Hermes de una cuenta. El propio
# Provisionador sabe crear el contenedor si la cuenta aún no lo tiene.
#
# La comunicación real es HTTP contra el endpoint del Provisionador (config global). Para
# poder desarrollar/probar sin infraestructura viva, el mecanismo concreto vive en un
# ADAPTADOR intercambiable (ver InfraAdapter): HTTP real en producción, mock en pruebas.
class Jabvox::Hermes::ProvisionerClient
  Result = Struct.new(:success, :data, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(adapter: nil)
    @adapter = adapter || default_adapter
  end

  # ¿Configurado el Hermes Provisionador central? (URL + admin key de infraestructura)
  def self.configured?
    base_url.present? && admin_key.present?
  end

  def self.base_url
    GlobalConfigService.load('HERMES_PROVISIONER_URL', nil).to_s.strip
  end

  def self.admin_key
    GlobalConfigService.load('HERMES_PROVISIONER_ADMIN_KEY', nil).to_s.strip
  end

  # Pide al Provisionador crear (o reusar) la instancia Hermes de la cuenta. Idempotente:
  # si ya existe, devuelve la existente. Nunca entrega credenciales de BD ni admin globales.
  def ensure_instance(account)
    @adapter.create_or_get_instance(
      account_id: account.id,
      identity: JabvoxHermesIdentity.for_account(account).name_jabvox
    )
  end

  def instance_status(account)
    @adapter.get_instance(account_id: account.id)
  end

  def disable_instance(account)
    @adapter.disable_instance(account_id: account.id)
  end

  def restart_instance(account)
    @adapter.restart_instance(account_id: account.id)
  end

  private

  # HTTP real si el Provisionador está configurado; si no, mock (dev/pruebas).
  def default_adapter
    if self.class.configured?
      Jabvox::Hermes::InfraAdapter::Http.new(base_url: self.class.base_url, admin_key: self.class.admin_key)
    else
      Jabvox::Hermes::InfraAdapter::Mock.new
    end
  end
end
