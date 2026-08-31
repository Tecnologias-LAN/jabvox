# frozen_string_literal: true

# jabvox.email.send_test — envía la plantilla TAL CUAL a una dirección de prueba,
# SIN interpolar: sirve para revisar el diseño, no para escribir a un contacto.
class Jabvox::Flows::Nodes::Jabvox::EmailSendTestNode < Jabvox::Flows::Nodes::Jabvox::EmailBase
  type 'jabvox.email.send_test'
  label 'Enviar Email de prueba'

  def perform
    config = smtp_config!
    template = find_template!(param(:templateId))
    to = valid_email!(param(:to), 'el email destino')

    result = deliver!(config: config, to: to, source: 'flow',
                      subject: template.subject.to_s, html_body: template.body.to_s)
    result.merge('template_id' => template.id, 'template_name' => template.name)
  end
end
