module Jabvox::AccountAiChatFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_ai_chat_enabled_jabvox? if name.to_s == 'jabvox_ai_chat'

    super
  end

  def enabled_features
    super.merge('jabvox_ai_chat' => jabvox_ai_chat_enabled_jabvox?)
  end
end
