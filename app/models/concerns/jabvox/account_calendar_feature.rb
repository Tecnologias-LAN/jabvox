# frozen_string_literal: true

module Jabvox::AccountCalendarFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_calendar_enabled_jabvox? if name.to_s == 'jabvox_calendar'

    super
  end

  def enabled_features
    super.merge('jabvox_calendar' => jabvox_calendar_enabled_jabvox?)
  end
end
