# Resuelve los valores de las variables de una plantilla de WhatsApp a partir del mapeo
# que el usuario configuró en la automatización.
#
# El mapeo dice, por cada variable ({{1}}, {{2}}...), de dónde sale su valor:
#   { "1" => { "source" => "contact", "field" => "name" },
#     "2" => { "source" => "task",    "field" => "title" },
#     "3" => { "source" => "custom",  "field" => "ciudad" },
#     "4" => { "source" => "fixed",   "value" => "Noviembre" } }
#
# Devuelve { "1" => "Ana", "2" => "Llamar", ... } listo para processed_params.
class Jabvox::AutomationTemplateParamsService
  # Campos ofrecidos en el selector del panel. Solo estos se pueden leer: el mapeo viene
  # del formulario, así que un `field` arbitrario no debe poder alcanzar cualquier método
  # del modelo (`send(field)` sería una vía para leer tokens o atributos internos).
  CONTACT_FIELDS = %w[name email phone_number identifier].freeze
  # Nombres reales de las columnas del modelo (llevan sufijo `_jabvox`), más los campos
  # derivados que resuelve TASK_EXTRACTORS.
  TASK_FIELDS = %w[title_jabvox description_jabvox priority_jabvox
                   due_date assignee_name stage_name board_name].freeze

  def initialize(mapping:, contact: nil, task: nil, stage: nil)
    @mapping = mapping.is_a?(Hash) ? mapping : {}
    @contact = contact
    @task = task
    @stage = stage
  end

  # Claves de parámetro válidas: POSICIONALES ({{1}}) o NOMBRADAS ({{nomcliente}}). Meta admite
  # en el nombre letras, dígitos y guion bajo. Antes solo se aceptaban numéricas, así que las
  # plantillas con variables nombradas perdían todo su mapeo al ejecutarse la automatización.
  VALID_PARAM_KEY = /\A[a-zA-Z0-9_]+\z/

  def call
    @mapping.each_with_object({}) do |(position, spec), out|
      next unless position.to_s.match?(VALID_PARAM_KEY)

      out[position.to_s] = value_for(spec.is_a?(Hash) ? spec.stringify_keys : {}).to_s
    end
  end

  private

  def value_for(spec)
    case spec['source']
    when 'contact' then contact_value(spec['field'])
    when 'task'    then task_value(spec['field'])
    when 'custom'  then custom_value(spec['field'])
    when 'fixed'   then spec['value']
    end
  end

  def contact_value(field)
    return nil if @contact.blank? || CONTACT_FIELDS.exclude?(field.to_s)

    @contact.public_send(field)
  end

  def custom_value(field)
    return nil if @contact.blank? || field.blank?

    # Los personalizados viven en un hash, así que no hay riesgo de invocar métodos.
    @contact.custom_attributes.to_h[field.to_s]
  end

  # Un extractor por campo derivado: la alternativa era un `case` lleno de `&.` encadenados,
  # que ocultaba qué devuelve cada campo.
  TASK_EXTRACTORS = {
    # El responsable principal está en `assignee`; `task_assignees` son los adicionales.
    'assignee_name' => lambda { |task, _stage|
      task.assignee&.name || task.task_assignees.first&.user&.name
    },
    'stage_name' => ->(task, stage) { stage&.name_jabvox || task.try(:stage)&.name_jabvox },
    'board_name' => ->(task, _stage) { task.try(:board)&.name_jabvox },
    'due_date' => ->(task, _stage) { task.due_at_jabvox&.strftime('%d/%m/%Y') }
  }.freeze

  def task_value(field)
    key = field.to_s
    return nil if @task.blank? || TASK_FIELDS.exclude?(key)

    extractor = TASK_EXTRACTORS[key]
    return extractor.call(@task, @stage) if extractor

    @task.public_send(key)
  end
end
