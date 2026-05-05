module Jabvox::AccountLeadsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_leads_enabled_jabvox? if name.to_s == 'jabvox_leads'

    super
  end

  def enabled_features
    super.merge('jabvox_leads' => jabvox_leads_enabled_jabvox?)
  end
end
