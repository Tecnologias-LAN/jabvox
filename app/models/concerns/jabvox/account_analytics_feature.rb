module Jabvox::AccountAnalyticsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_analytics_enabled_jabvox? if name.to_s == 'jabvox_analytics'

    super
  end

  def enabled_features
    super.merge('jabvox_analytics' => jabvox_analytics_enabled_jabvox?)
  end
end
