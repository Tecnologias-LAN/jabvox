# frozen_string_literal: true

# Chat Aprovisionador: RELAY puro hacia el Hermes Aprovisionador global.
#
# Jabvox NO aprovisiona ni crea MCPs. La cuenta ligada al Hermes Aprovisionador le pide
# cosas a ESE Hermes (que ya sabe crear/ligar el Hermes de la cuenta y sus MCPs). Jabvox
# solo transporta el mensaje y muestra la respuesta; el aprovisionador confirma el resultado
# por el webhook /webhooks/jabvox/hermes/provisioned. Nunca toca ContextForge.
# rubocop:disable Style/ClassAndModuleChildren
module Jabvox
  class ProvisioningChatService
    def initialize(account:, user:)
      @account = account
      @user = user
    end

    # @return [Hash] { reply:, metadata: }
    def handle(content)
      return reply(no_link_msg, metadata: { via: 'provisioner', ok: false }) unless linked?

      route_to_provisioner(content)
    rescue StandardError => e
      Rails.logger.error("[ProvisioningChat] account=#{@account.id} error=#{e.class}")
      reply("Ocurrió un error procesando tu solicitud: #{e.message}")
    end

    private

    def linked?
      JabvoxHermesProvisionerLink.active_for?(@account.id)
    end

    # Envía el mensaje al Hermes Aprovisionador global. El aprovisionador razona y ejecuta
    # con sus MCPs de infraestructura; Jabvox solo transporta.
    def route_to_provisioner(content)
      result = Jabvox::Hermes::ProvisionerChatRelay.new(account: @account, user: @user).send_message(content)
      if result.success?
        reply(result.text, metadata: { via: 'provisioner' })
      else
        reply("El aprovisionador no pudo responder: #{result.error}", metadata: { via: 'provisioner', ok: false })
      end
    end

    def no_link_msg
      'Esta cuenta no está ligada a un Hermes Aprovisionador. Un administrador debe ligarla ' \
        'desde Super Admin → Hermes antes de poder usar el Chat Aprovisionador.'
    end

    def reply(text, metadata: {})
      { reply: text, metadata: metadata }
    end
  end
end
# rubocop:enable Style/ClassAndModuleChildren
