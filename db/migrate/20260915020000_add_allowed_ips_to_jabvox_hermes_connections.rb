# Allowlist de origen para los requests ENTRANTES de un Hermes
# (/webhooks/jabvox/hermes_agent/*). Hasta ahora bastaba con el action_token: un token
# filtrado podía ejecutar tools sobre la cuenta desde cualquier IP de internet. Con esta
# columna, cada conexión declara desde qué IPs o rangos acepta ejecutar.
#
# La política es fail-closed y vive en el modelo (ver JabvoxHermesConnection#ip_allowed?):
# una conexión sin IPs declaradas no acepta NINGÚN request entrante.
class AddAllowedIpsToJabvoxHermesConnections < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_hermes_connections, :allowed_ips_jabvox, :string, array: true, default: [], null: false
  end
end
