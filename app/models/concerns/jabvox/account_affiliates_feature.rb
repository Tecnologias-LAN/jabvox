# frozen_string_literal: true

module Jabvox::AccountAffiliatesFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_affiliates_enabled_jabvox? if name.to_s == 'jabvox_affiliates'

    super
  end

  def enabled_features
    super.merge('jabvox_affiliates' => jabvox_affiliates_enabled_jabvox?)
  end
end
