# frozen_string_literal: true

# Normaliza a E.164 los teléfonos heredados de producción.
#
# En producción conviven tres formatos, todos de Colombia:
#   "+573001234567"  ya correcto, no se toca
#   "573001234567"   le falta el "+"
#   "3001234567"     le falta el país entero
#
# Los dos últimos entraron por caminos que saltaban la validación del modelo.
# Mientras existan, dos filas que son la MISMA persona no se reconocen como
# duplicadas, y el contacto no aparece al buscar por su número con prefijo.
#
# Uso (primero SIEMPRE en simulación):
#
#   # 1. Ver qué cambiaría, sin escribir nada:
#   bundle exec rake jabvox:phones:normalize
#
#   # 2. Aplicar de verdad:
#   bundle exec rake jabvox:phones:normalize APPLY=1
#
#   # Otras opciones:
#   ACCOUNT_ID=2      solo una cuenta (recomendado para la primera pasada)
#   COUNTRY=CO        país con el que completar los números locales (por defecto CO)
#   LIMIT=500         procesar como mucho N contactos
#
# Seguridad: nunca fusiona ni borra contactos. Si el número ya normalizado
# chocaría con otro contacto de la misma cuenta, esa fila se SALTA y se reporta
# como conflicto, para revisarla a mano.
namespace :jabvox do
  namespace :phones do
    desc 'Normaliza a E.164 los teléfonos heredados (simulación por defecto; APPLY=1 para aplicar)'
    task normalize: :environment do
      Jabvox::PhoneNormalizeTask.new(
        apply: ENV['APPLY'].present?,
        account_id: ENV['ACCOUNT_ID'].presence,
        country: ENV.fetch('COUNTRY', 'CO'),
        limit: ENV['LIMIT'].presence&.to_i
      ).run
    end
  end
end
