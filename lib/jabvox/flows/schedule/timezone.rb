# frozen_string_literal: true

# Resolución de la ZONA HORARIA de un disparador programado.
#
# POR QUÉ EXISTE: el servidor corre en UTC, así que un "9am" configurado por el
# usuario se evaluaba contra las 09:00 UTC — las 04:00 en Colombia. La hora se
# interpreta ahora en la zona del propio nodo.
module Jabvox::Flows::Schedule::Timezone
  module_function

  # Zona válida, o nil (hora del servidor). Una zona irreconocible NO lanza:
  # degrada al comportamiento de siempre en vez de tumbar el barrido.
  def resolve(raw)
    name = raw.to_s.strip
    return nil if name.empty?

    zone = ActiveSupport::TimeZone[name]
    return zone if zone

    Rails.logger.warn("Zona horaria '#{name}' no reconocida en un disparador programado: " \
                      'se usa la hora del servidor.')
    nil
  end

  # `now` situado en la zona pedida (o en la del servidor si es nil).
  def at(now, zone)
    zone ? now.in_time_zone(zone) : now
  end
end
