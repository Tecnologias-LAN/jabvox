module Jabvox::AccountDataExportFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_data_export_enabled_jabvox? if name.to_s == 'jabvox_data_export'

    super
  end

  def enabled_features
    super.merge('jabvox_data_export' => jabvox_data_export_enabled_jabvox?)
  end
end
