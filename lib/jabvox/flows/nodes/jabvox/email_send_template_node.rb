# frozen_string_literal: true

# jabvox.email.send_template — envía una plantilla al email del CONTACTO,
# interpolando sus datos igual que el panel ("dispare este correo").
class Jabvox::Flows::Nodes::Jabvox::EmailSendTemplateNode < Jabvox::Flows::Nodes::Jabvox::EmailBase
  type 'jabvox.email.send_template'
  label 'Enviar plantilla de Email'

  def perform
    config = smtp_config!
    template = find_template!(param(:templateId))
    contact = find_contact!(param(:contactId))
    fail_with!(no_email_message(contact)) if contact.email.blank?

    result = deliver!(config: config, to: contact.email, source: 'flow',
                      subject: interpolate(template.subject, contact),
                      html_body: interpolate(template.body, contact))
    result.merge('template_id' => template.id, 'template_name' => template.name,
                 'contact_id' => contact.id)
  end

  private

  def no_email_message(contact)
    "El contacto #{contact.id} no tiene email, así que no hay a dónde enviar la plantilla. " \
      'Rellena el correo del contacto o filtra antes los que no lo tienen.'
  end
end
