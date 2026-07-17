module Jabvox::AccountLeadDeleteFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_lead_delete_enabled_jabvox? if name.to_s == 'jabvox_lead_delete'

    super
  end

  def enabled_features
    super.merge('jabvox_lead_delete' => jabvox_lead_delete_enabled_jabvox?)
  end
end
