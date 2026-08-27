# Expone el feature 'jabvox_tickets' (registro de tickets por la cuenta) mapeado a
# la columna jabvox_tickets_enabled_jabvox, siguiendo el patrón del resto de módulos.
module Jabvox::AccountTicketsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_tickets_enabled_jabvox? if name.to_s == 'jabvox_tickets'

    super
  end

  def enabled_features
    super.merge('jabvox_tickets' => jabvox_tickets_enabled_jabvox?)
  end
end
