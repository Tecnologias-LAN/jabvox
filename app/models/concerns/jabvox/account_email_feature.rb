module Jabvox::AccountEmailFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_email_enabled_jabvox? if name.to_s == 'jabvox_email'

    super
  end

  def enabled_features
    super.merge('jabvox_email' => jabvox_email_enabled_jabvox?)
  end
end
