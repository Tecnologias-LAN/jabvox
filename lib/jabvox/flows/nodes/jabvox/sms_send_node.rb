# frozen_string_literal: true

# jabvox.sms.send — envía un SMS al teléfono del contacto por un proveedor de la
# cuenta. El servicio NO lanza en fallo: devuelve el mensaje con status 'failed',
# así que aquí se comprueba el status REAL para no reportar un falso éxito.
class Jabvox::Flows::Nodes::Jabvox::SmsSendNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.sms.send'
  label 'Enviar SMS'

  def perform
    provider = find_provider!
    contact = find_contact!(param(:contactId))
    fail_with!(no_phone_message(contact)) if contact.phone_number.blank?

    sms = send_sms(provider, contact)
    fail_with!(failed_message(sms)) unless sms.status == 'sent'

    { 'sent' => true, 'status' => sms.status, 'smsId' => sms.id, 'phone' => sms.phone,
      'contact_id' => contact.id, 'provider_id' => provider.id, 'message' => sms.message }
  end

  private

  def send_sms(provider, contact)
    Jabvox::SmsSenderService.new(provider).send_sms(
      phone: contact.phone_number, message: message, account: account, contact: contact
    )
  end

  def find_provider!
    provider_id = require_id!(param(:providerId), 'el proveedor SMS')
    provider = account.jabvox_sms_providers.find_by(id: provider_id)
    fail_with!(missing_provider_message(provider_id)) if provider.nil?
    return provider if provider.active?

    fail_with!("El proveedor SMS \"#{provider.name}\" está INACTIVO: actívalo en Jabvox o elige otro.")
  end

  def missing_provider_message(provider_id)
    "El proveedor SMS #{provider_id} no existe en esta cuenta. Elige uno de la lista de " \
      'proveedores SMS de Jabvox.'
  end

  def message
    text = param(:message).to_s.strip
    if text.blank?
      fail_with!('Falta el mensaje del SMS: llegó vacío. Escribe el texto a enviar ' \
                 '(admite plantillas {{...}}).')
    end

    text
  end

  def no_phone_message(contact)
    "El contacto #{contact.id} no tiene número de teléfono, así que no hay a dónde enviar el SMS. " \
      'Filtra antes los contactos sin teléfono.'
  end

  # El status queda registrado en JabvoxSmsMessage: se publica el error del
  # proveedor en vez de dar el envío por bueno.
  def failed_message(sms)
    "El SMS no se pudo enviar (estado \"#{sms.status}\"): #{sms.error_message.presence || 'sin detalle del proveedor'}. " \
      'Revisa las credenciales y el saldo del proveedor SMS en Jabvox.'
  end
end
