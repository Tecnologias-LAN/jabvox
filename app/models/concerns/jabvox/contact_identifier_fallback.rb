# Un contacto sin email, teléfono ni identificador no es localizable por ningún módulo
# (dialer, importación, exportación externa), así que se le asigna uno derivado de su id.
#
# Esto vivía dentro del concern que además creaba el lead asociado. Al retirar Leads, la
# creación del lead desaparece pero el identificador sigue haciendo falta: sin él, un
# contacto creado sin datos de contacto queda inalcanzable.
module Jabvox::ContactIdentifierFallback
  extend ActiveSupport::Concern

  included do
    after_commit :jabvox_ensure_resolvable_contact, on: :create
  end

  private

  def jabvox_ensure_resolvable_contact
    return if email.present? || phone_number.present? || identifier.present?

    update_columns(identifier: "jabvox_#{id}") # rubocop:disable Rails/SkipsModelValidations
  rescue StandardError => e
    Rails.logger.error("No se pudo asignar identificador al contacto #{id}: #{e.message}")
  end
end
