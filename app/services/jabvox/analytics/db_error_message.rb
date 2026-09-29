# frozen_string_literal: true

# Traduce el error de una base externa en algo que el usuario pueda accionar.
#
# Antes cualquier fallo devolvía "No se pudo completar la operación contra la fuente de
# datos": con eso nadie podía saber si le faltaba una coma, si una columna no existía o si
# la consulta había excedido el tiempo.
#
# Solo se muestran los fallos de CONSULTA. Un error de credenciales, de red o de permisos
# sigue devolviendo el mensaje genérico, para no filtrar usuario, host ni topología.
class Jabvox::Analytics::DbErrorMessage
  GENERIC = 'No se pudo completar la operación contra la fuente de datos'

  # Fallos que describen la consulta del usuario y por tanto son seguros de mostrar.
  SAFE = /
    (syntax\ error|unknown\ column|no\ such\ column|doesn't\ exist|does\ not\ exist|
     unknown\ table|invalid\ column|ambiguous|division\ by\ zero|
     out\ of\ range|data\ too\ long|timeout|timed\ out)
  /xi

  MAX_LENGTH = 200

  def initialize(error)
    @error = error
  end

  def call
    detail = safe_detail
    return GENERIC if detail.blank?

    "La base rechazó la consulta: #{detail}"
  end

  private

  # Solo la primera línea: el resto suele traer el SQL completo y el contexto de conexión.
  def safe_detail
    first_line = @error.message.to_s.lines.first.to_s.strip
    return nil unless first_line.match?(SAFE)

    first_line.sub(/\A[A-Z][\w:]*Error:\s*/, '').delete('"').truncate(MAX_LENGTH)
  end
end
