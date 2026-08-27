# frozen_string_literal: true

# Feature flag del módulo "Chat Aprovisionamiento" (jabvox_ai_chat_provisioning): la cuenta
# ligada desde la que se le pide a Hermes crear/aprovisionar MCPs. Se habilita por cuenta
# desde el super admin (columna booleana), igual que el resto de módulos Jabvox.
module Jabvox::AccountAiChatProvisioningFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_ai_chat_provisioning_enabled_jabvox? if name.to_s == 'jabvox_ai_chat_provisioning'

    super
  end

  def enabled_features
    super.merge('jabvox_ai_chat_provisioning' => jabvox_ai_chat_provisioning_enabled_jabvox?)
  end
end
