# == Schema Information
#
# Table name: account_automation_configs
#
#  id                     :bigint           not null, primary key
#  api_key_jabvox         :text
#  api_key_prefix_jabvox  :string
#  api_key_set_at_jabvox  :datetime
#  enabled                :boolean          default(FALSE), not null
#  last_error             :text
#  last_provisioned_at    :datetime
#  last_status            :string
#  max_flows              :integer
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  remote_account_id      :bigint
#
# Indexes
#
#  index_account_automation_configs_on_account_id_unique  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class AccountAutomationConfig < ApplicationRecord
  self.table_name = 'account_automation_configs'

  # Formato de las API keys que emite Automations (ver ApiKeysService de ese
  # repo: `jbx_` + 32 hex). Validamos el formato en Jabvox para que un pegado
  # con espacios o truncado falle AQUÍ, con un mensaje claro, en vez de acabar
  # en un 401 opaco de la plataforma remota.
  API_KEY_FORMAT = /\Ajbx_[0-9a-f]{32}\z/
  # Cuántos caracteres del final se muestran en el enmascarado `•••• abcd`.
  API_KEY_VISIBLE_SUFFIX = 4

  belongs_to :account

  # Cifrado en reposo con Active Record Encryption, mismo patrón que el resto de
  # credenciales del fork (JabvoxSaldoConfig, JabvoxCdrConfig, etc.): el guard
  # `Jabvox.encryption_configured?` evita romper las instalaciones que todavía
  # no tienen configuradas las claves ACTIVE_RECORD_ENCRYPTION_*.
  #
  # NO es determinista: nunca se busca una cuenta por su api_key (Jabvox siempre
  # llega a la config por account_id), así que no hace falta sacrificar la
  # aleatoriedad del ciphertext.
  encrypts :api_key_jabvox if Jabvox.encryption_configured?

  validates :account_id, uniqueness: true
  # max_flows nil = ilimitado; si viene, debe ser positivo.
  validates :max_flows, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  # nil/blank = la cuenta no tiene key propia y cae a la Provision Key maestra.
  validates :api_key_jabvox, format: { with: API_KEY_FORMAT, message: I18n.t('errors.messages.invalid') },
                             allow_blank: true

  scope :enabled, -> { where(enabled: true) }

  # ¿Esta cuenta tiene credencial propia? Es lo que decide en
  # Automations::ProvisioningService si se usa X-Api-Key o la maestra.
  def own_api_key?
    api_key_jabvox.present?
  end

  # Asigna la key y deriva el prefijo visible + la marca de tiempo en el mismo
  # paso, para que las tres columnas no puedan quedar descuadradas.
  # Un valor en blanco BORRA la credencial (volviendo a la maestra); el
  # controlador se encarga de que "campo vacío" signifique "conservar", así que
  # aquí un blank es una petición explícita de borrado.
  def assign_api_key(raw)
    value = raw.to_s.strip
    if value.blank?
      self.api_key_jabvox = nil
      self.api_key_prefix_jabvox = nil
      self.api_key_set_at_jabvox = nil
    else
      self.api_key_jabvox = value
      self.api_key_prefix_jabvox = value[0, 8]
      self.api_key_set_at_jabvox = Time.current
    end
  end

  # Representación segura para la UI del super admin: nunca la key completa.
  #
  # Se muestra el PREFIJO (los 8 primeros caracteres) porque es exactamente el
  # mismo dato que el panel de Automations expone en su listado de credenciales
  # (`value.slice(0, 8)`), así que permite cotejar de un vistazo si la key que
  # tiene Jabvox es la última que se regeneró allí.
  #
  # El sufijo es corto a propósito: entre prefijo y sufijo se revelan 12 de los
  # 36 caracteres, y los 24 restantes (96 bits de aleatoriedad) siguen siendo
  # inadivinables. Si el prefijo no está disponible (cuentas cuya key se guardó
  # antes de que existiera la columna), degrada a solo el sufijo.
  def masked_api_key
    return nil unless own_api_key?

    suffix = api_key_jabvox.to_s.last(API_KEY_VISIBLE_SUFFIX)
    prefix = api_key_prefix_jabvox.presence
    prefix ? "#{prefix}…•••• #{suffix}" : "•••• #{suffix}"
  end
end
