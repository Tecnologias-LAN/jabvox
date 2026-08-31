# frozen_string_literal: true

# trigger.manual — arranca solo cuando el usuario pulsa "Ejecutar". No tiene
# handler: el motor siembra `{{trigger.*}}` con lo que llegue del lanzamiento.
class Jabvox::Flows::Nodes::Triggers::ManualNode
  TYPE = 'trigger.manual'
  LABEL = 'Manual'

  def self.register_on(registry)
    registry.register(TYPE, label: LABEL)
  end

  # Un disparador manual siempre casa: quien lo lanza ya eligió el nodo.
  def self.matches?(_node, _payload = {})
    true
  end
end
