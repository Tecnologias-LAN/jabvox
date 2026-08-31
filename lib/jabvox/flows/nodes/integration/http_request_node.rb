# frozen_string_literal: true

# integration.http_request — petición HTTP arbitraria a un tercero, con guard
# anti-SSRF. No sigue redirecciones: una 302 burlaría la validación de la URL.
class Jabvox::Flows::Nodes::Integration::HttpRequestNode < Jabvox::Flows::Nodes::Integration::Base
  type 'integration.http_request'
  label 'Petición HTTP'

  def perform
    result = http_call(method: param(:method), url: param(:url), headers: param(:headers),
                       body: param(:body), timeout_ms: param(:timeoutMs))

    with_status(result, result['status'])
  end
end
