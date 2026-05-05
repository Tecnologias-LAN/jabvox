module Jabvox::AccountResponseBotFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_response_bot_enabled_jabvox? if name.to_s == 'jabvox_response_bot'

    super
  end

  def enabled_features
    super.merge('jabvox_response_bot' => jabvox_response_bot_enabled_jabvox?)
  end
end
