# frozen_string_literal: true

# jabvox.email.send_message — correo libre (asunto y cuerpo propios, sin
# plantilla) a UNA dirección. Es el nodo del "informe final del flujo".
class Jabvox::Flows::Nodes::Jabvox::EmailSendMessageNode < Jabvox::Flows::Nodes::Jabvox::EmailBase
  type 'jabvox.email.send_message'
  label 'Enviar correo'

  def perform
    config = smtp_config!
    to = valid_email!(param(:to), 'el correo destino')
    subject = first_filled(param(:subject))
    fail_with!('Falta el asunto del correo: llegó vacío.') if subject.blank?

    deliver!(config: config, to: to, subject: subject, html_body: html_body, source: 'flow')
  end

  private

  # Texto plano por defecto: se escapa y se respetan los saltos de línea, que es
  # lo que espera quien pega el informe de un bucle.
  def html_body
    body = param(:body).to_s
    fail_with!(empty_body_message) if body.strip.blank?
    return body if opt_in?(param(:isHtml))

    ERB::Util.html_escape(body).gsub("\n", '<br>')
  end

  def empty_body_message
    'Falta el mensaje del correo: llegó vacío. Si lo tomas de otro paso, comprueba que ' \
      'esa referencia trae texto.'
  end
end
