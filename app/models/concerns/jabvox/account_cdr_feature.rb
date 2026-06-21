module Jabvox::AccountCdrFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_cdr_enabled_jabvox? if name.to_s == 'jabvox_cdr'

    super
  end

  def enabled_features
    super.merge('jabvox_cdr' => jabvox_cdr_enabled_jabvox?)
  end
end
