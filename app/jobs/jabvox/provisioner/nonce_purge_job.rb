# frozen_string_literal: true

# Purga los nonces de la API Provisioner ya caducados. Un nonce solo puede usarse para un
# replay mientras su timestamp siga dentro de la ventana de firma; pasada esa ventana el
# propio chequeo de tiempo rechaza la petición, así que conservarlo no aporta seguridad y
# solo hace crecer la tabla sin límite (una fila por request autenticada).
# Programado en config/schedule.yml.
class Jabvox::Provisioner::NoncePurgeJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    JabvoxProvisionerNonce.purge_expired!
  end
end
