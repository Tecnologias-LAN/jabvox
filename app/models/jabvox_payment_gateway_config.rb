# frozen_string_literal: true

# Configuración de la pasarela de pago, editable desde Super Admin. Guarda el proveedor
# activo (bold/wompi/mono), su token/llave PÚBLICA, la URL de checkout, el modo sandbox y
# los SECRETOS (api_key privada, secret_key de firma de webhook) CIFRADOS en reposo con
# ActiveRecord::Encryption. El super admin los administra desde el panel; ya no viven en
# variables de entorno.
#
# Solo puede haber UNA pasarela activa a la vez (índice parcial en la BD).
# == Schema Information
#
# Table name: jabvox_payment_gateway_configs
#
#  id                :bigint           not null, primary key
#  active            :boolean          default(FALSE), not null
#  api_key           :text
#  checkout_base_url :string
#  provider          :string           not null
#  public_token      :string
#  sandbox           :boolean          default(FALSE), not null
#  secret_key        :text
#  settings          :jsonb            not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#
# Indexes
#
#  idx_one_active_gateway                            (active) UNIQUE WHERE (active = true)
#  index_jabvox_payment_gateway_configs_on_provider  (provider) UNIQUE
#
class JabvoxPaymentGatewayConfig < ApplicationRecord
  PROVIDERS = %w[bold wompi mono].freeze

  # Secretos cifrados en reposo (mismo mecanismo que User#otp_secret). Nunca se
  # devuelven en serializaciones ni se muestran en el panel; solo los lee el adaptador
  # de la pasarela server-to-server.
  encrypts :api_key
  encrypts :secret_key

  validates :provider, presence: true, inclusion: { in: PROVIDERS }, uniqueness: true

  after_save :deactivate_others, if: :saved_change_to_active?

  # La pasarela activa actualmente (o nil si no hay ninguna).
  def self.active_gateway
    find_by(active: true)
  end

  # Vincular = activar esta pasarela como la que cobra (desactiva las demás).
  def link!
    update!(active: true)
  end

  # Desvincular = dejar de usar esta pasarela para cobrar. Si no queda ninguna activa,
  # el checkout responde no_active_gateway (no se puede cobrar hasta vincular otra).
  # NOTA: aquí "forma de pago" = qué pasarela cobra. NO se guardan tarjetas de clientes:
  # Bold no ofrece tokenización/suscripción, así que no hay dato de tarjeta que guardar
  # ni desvincular; el cobro es siempre por link de pago puntual.
  def unlink!
    update!(active: false)
  end

  private

  # Garantiza una sola activa: al activar esta, desactiva el resto.
  def deactivate_others
    return unless active?

    self.class.where.not(id: id).where(active: true).update_all(active: false) # rubocop:disable Rails/SkipsModelValidations
  end
end
