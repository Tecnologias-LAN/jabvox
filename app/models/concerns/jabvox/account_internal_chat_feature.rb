# frozen_string_literal: true

module Jabvox::AccountInternalChatFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_internal_chat_enabled_jabvox? if name.to_s == 'jabvox_internal_chat'

    super
  end

  def enabled_features
    super.merge('jabvox_internal_chat' => jabvox_internal_chat_enabled_jabvox?)
  end
end
