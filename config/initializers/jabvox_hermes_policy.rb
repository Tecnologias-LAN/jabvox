# frozen_string_literal: true

# Garantía de política de seguridad de Hermes en cada arranque.
#
# El token entregado a Hermes solo puede LEER, CREAR y EDITAR: borrar registros de Jabvox
# está prohibido a nivel de arquitectura. Si alguien introduce una tool destructiva en el
# ToolRegistry, la app debe FALLAR AL ARRANCAR en vez de exponer la capacidad silenciosamente.
#
# Se ejecuta tras la inicialización para que las constantes autoload ya estén disponibles.
Rails.application.config.after_initialize do
  Jabvox::Hermes::ToolRegistry.assert_no_destructive_tools!
rescue StandardError => e
  # En producción, un catálogo destructivo es un fallo de seguridad: abortar el arranque.
  # En entornos de asset-precompile (sin app cargada) no rompemos el build.
  raise e unless Rails.env.test? && ENV['SKIP_HERMES_POLICY_CHECK'] == 'true'
end
