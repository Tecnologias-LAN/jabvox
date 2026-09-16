# Pure compiler: screens_json (Jabvox's internal builder format, architecture doc
# section 4.3) -> Flow JSON 7.3 as Meta expects it (section 2.2). No I/O. Reused both
# for the read-only JSON preview tab and for the real publish (PublishService).
#
# Screens without an endpoint (the only kind this v1 supports, doc section 2.4) never
# set routing_model/data_channel_uri — Meta infers routing from the navigate actions.
class Jabvox::WhatsappFlows::JsonCompiler
  FLOW_JSON_VERSION = '7.3'.freeze
  # Nombre del Form que envuelve los componentes de cada pantalla. Meta solo
  # resuelve ${form.campo} dentro de un Form; el nombre en sí es libre.
  FORM_NAME = 'flow_path'.freeze
  # Componentes que capturan una respuesta y por tanto viajan en el payload.
  INPUT_TYPES = %w[
    TextInput TextArea RadioButtonsGroup CheckboxGroup Dropdown
    ChipsSelector DatePicker OptIn
  ].freeze

  def initialize(flow_or_screens)
    @screens = flow_or_screens.respond_to?(:screens_json) ? flow_or_screens.screens_json : flow_or_screens
  end

  def call
    ordered = Array(@screens).sort_by { |s| s['order'] || s[:order] || 0 }
    {
      version: FLOW_JSON_VERSION,
      screens: ordered.each_with_index.map { |screen, index| compile_screen(screen, ordered[0...index]) }
    }
  end

  private

  # `previous` son las pantallas anteriores, necesarias para arrastrar sus
  # respuestas hasta el final (ver inherited_fields).
  def compile_screen(screen, previous = [])
    fields = field_names(screen)
    inherited = inherited_fields(previous)
    children = components_of(screen).map { |c| compile_component(c, fields, inherited) }

    {
      id: at(screen, :id),
      title: at(screen, :title),
      terminal: at(screen, :terminal).present?,
      data: screen_data(screen, previous),
      layout: {
        type: 'SingleColumnLayout',
        # Meta solo resuelve las referencias ${form.campo} si los componentes
        # viven dentro de un Form. Sin esta envoltura el payload llega vacío.
        children: [{ type: 'Form', name: FORM_NAME, children: children }]
      }
    }.compact
  end

  # screens_json llega con claves string o símbolo según venga de la base de
  # datos o del controlador, así que se leen por ambas.
  def at(hash, key)
    return nil unless hash.is_a?(Hash)

    hash[key.to_s] || hash[key.to_sym]
  end

  def components_of(screen)
    Array(at(screen, :components))
  end

  # Nombre del campo que captura un componente, o nil si no captura ninguno.
  def field_name_of(component)
    return nil unless INPUT_TYPES.include?(at(component, :type).to_s)

    at(at(component, :props) || {}, :name).presence
  end

  # Nombres de los campos que captura esta pantalla, en orden.
  def field_names(screen)
    components_of(screen).filter_map { |component| field_name_of(component) }
  end

  # Campos recogidos en pantallas anteriores. Cada pantalla los recibe en su
  # `data` y los reenvía, que es como Meta los hace llegar hasta el complete
  # final: sin esto solo volverían las respuestas de la última pantalla.
  def inherited_fields(previous)
    previous.flat_map { |screen| field_names(screen) }.uniq
  end

  # Meta exige declarar en `data` cada campo que la pantalla recibe de una
  # anterior, con su tipo y un ejemplo.
  def screen_data(screen, previous)
    declared = at(screen, :data) || {}
    inherited = inherited_fields(previous)
    return declared if inherited.empty?

    types = component_types(previous)
    inherited.each_with_object(declared.dup) do |field, out|
      out[field] = data_descriptor(types[field])
    end
  end

  def component_types(screens)
    screens.each_with_object({}) do |screen, out|
      components_of(screen).each do |component|
        name = field_name_of(component)
        out[name] = at(component, :type).to_s if name
      end
    end
  end

  # CheckboxGroup devuelve varias opciones (array); el resto, un texto.
  def data_descriptor(component_type)
    return { 'type' => 'array', 'items' => { 'type' => 'string' }, '__example__' => [] } if component_type == 'CheckboxGroup'

    { 'type' => 'string', '__example__' => 'Ejemplo' }
  end

  def compile_component(component, fields = [], inherited = [])
    type = component['type'] || component[:type]
    props = component['props'] || component[:props] || {}

    { type: type }.merge(compile_props(type, props, fields, inherited))
  end

  # snake_case builder keys -> kebab-case Meta keys, via the shared catalog map
  # (Jabvox::WhatsappFlows::ComponentCatalog::PROP_KEY_MAP), so this stays in sync
  # with whatever Validator also treats as a known prop.
  #
  # `action` is handled separately: Meta has no generic "action" key on a component —
  # Footer/EmbeddedLink emit on-click-action, selection components emit
  # on-select-action, per ComponentCatalog.action_prop_key. A component type with no
  # mapped action key (e.g. a stray `action` prop on a text component) simply drops it.
  def compile_props(type, props, fields = [], inherited = [])
    props.each_with_object({}) do |(key, value), out|
      if key.to_s == 'action'
        meta_key = Jabvox::WhatsappFlows::ComponentCatalog.action_prop_key(type)
        out[meta_key.to_sym] = compile_action(value, fields, inherited) if meta_key
        next
      end

      # Una propiedad que el usuario dejó en blanco no se manda: Meta rechaza el
      # Flow al publicarlo ("Property 'init-value' is not allowed"), no la ignora.
      next if blank_prop?(value)

      meta_key = Jabvox::WhatsappFlows::ComponentCatalog.meta_prop_key(key)
      out[meta_key.to_sym] = compile_value(value)
    end
  end

  # Solo se descartan los vacíos: `false` y `0` son valores legítimos.
  def blank_prop?(value)
    value.nil? || value == '' || (value.is_a?(Array) && value.empty?)
  end

  # Meta espera el destino de un `navigate` como objeto
  # ({ type: 'screen', name: 'ID' }), no como el id suelto que guarda el
  # builder. Sin esta traducción el Flow se rechaza al publicarlo.
  #
  # Además le añade el `payload`: Meta solo devuelve (en el complete) o propaga
  # a la pantalla siguiente (en el navigate) los campos que la acción declara
  # explícitamente. Sin payload la respuesta del formulario llega vacía, con
  # solo el flow_token.
  def compile_action(action, fields = [], inherited = [])
    compiled = compile_value(action)
    return compiled unless compiled.is_a?(Hash)

    compiled = compiled.merge('payload' => action_payload(fields, inherited)) if payload_action?(compiled)

    target = compiled['next']
    return compiled unless compiled['name'].to_s == 'navigate' && target.is_a?(String)

    compiled.merge('next' => { 'type' => 'screen', 'name' => target })
  end

  def payload_action?(compiled)
    %w[complete navigate data_exchange].include?(compiled['name'].to_s) && compiled['payload'].blank?
  end

  # Los campos de esta pantalla se leen del formulario; los de pantallas
  # anteriores, del `data` que la pantalla recibió.
  def action_payload(fields, inherited)
    payload = fields.index_with { |field| "${form.#{field}}" }
    inherited.each_with_object(payload) { |field, out| out[field] = "${data.#{field}}" }
  end

  def compile_value(value)
    case value
    when Hash
      value.each_with_object({}) { |(k, v), h| h[k.to_s] = compile_value(v) }
    when Array
      value.map { |v| compile_value(v) }
    else
      value
    end
  end
end
