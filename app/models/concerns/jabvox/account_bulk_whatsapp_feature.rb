module Jabvox::AccountBulkWhatsappFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_bulk_whatsapp_enabled_jabvox? if name.to_s == 'jabvox_bulk_whatsapp'

    super
  end

  def enabled_features
    super.merge('jabvox_bulk_whatsapp' => jabvox_bulk_whatsapp_enabled_jabvox?)
  end
end
