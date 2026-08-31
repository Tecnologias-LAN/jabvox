# frozen_string_literal: true

# Base común de los nodos `jabvox.email.*`: SMTP de la cuenta, plantillas y la
# misma interpolación que usa el panel (`email_templates_controller`).
class Jabvox::Flows::Nodes::Jabvox::EmailBase < Jabvox::Flows::Nodes::Jabvox::Base
  EMAIL_FORMAT = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/

  private

  # SMTP de la cuenta. Sin `address` no hay servidor al que entregar: el envío
  # fallaría dentro de Mail con un error ilegible.
  def smtp_config!
    config = account.jabvox_smtp_config
    return config if config&.address.present?

    fail_with!('Esta cuenta no tiene SMTP configurado en Jabvox, así que no se puede enviar correo. ' \
               'Configúralo en Ajustes > Email de Jabvox.')
  end

  def find_template!(raw, label = 'la plantilla')
    template_id = require_id!(raw, label)
    template = account.jabvox_email_templates.find_by(id: template_id)
    return template if template

    fail_with!("La plantilla de correo #{template_id} no existe en esta cuenta. " \
               'Elige una plantilla de la lista.')
  end

  def valid_email!(raw, label)
    address = first_filled(raw)
    fail_with!("Falta #{label}: llegó vacío. Escribe la dirección a la que enviar.") if address.blank?
    return address if EMAIL_FORMAT.match?(address)

    fail_with!("#{label.capitalize} no es válido: \"#{address}\".")
  end

  # Misma sustitución que `deliver_template` del panel: si cambia allí, cambia aquí.
  def interpolate(text, contact)
    text.to_s
        .gsub('{{contact_name}}', contact.name.to_s)
        .gsub('{{contact_email}}', contact.email.to_s)
        .gsub('{{contact_phone}}', contact.phone_number.to_s)
  end

  def deliver!(config:, to:, subject:, html_body:, source:)
    Jabvox::EmailSenderService.new(
      account: account, config: config, to: to,
      subject: subject, html_body: html_body, source: source, user: nil
    ).deliver!
    { 'sent' => true, 'to' => to, 'subject' => subject }
  rescue StandardError => e
    fail_with!("No se pudo enviar el correo a #{to}: #{e.message}. Revisa el SMTP de la cuenta.")
  end
end
