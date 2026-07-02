module Jabvox::AccountLeadImportFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_lead_import_enabled_jabvox? if name.to_s == 'jabvox_lead_import'

    super
  end

  def enabled_features
    super.merge('jabvox_lead_import' => jabvox_lead_import_enabled_jabvox?)
  end
end
