# Local, pre-Meta validation of a Flow's screens_json (architecture doc section 5.1).
# Pure — no I/O, no Graph API calls. Used before allowing a save to move to
# 'ready'/'validating' status and before PublishService ever touches Meta.
#
# Usage:
#   result = Jabvox::WhatsappFlows::Validator.new(flow).call
#   result => { valid: true/false, errors: [{ screen_id:, component_id:, field:, message: }] }
class Jabvox::WhatsappFlows::Validator
  Catalog = Jabvox::WhatsappFlows::ComponentCatalog

  def initialize(flow)
    @flow = flow
    @errors = []
  end

  def call
    validate_name_and_category
    screens = Array(@flow.screens_json)
    if screens.blank?
      add_error(nil, nil, 'screens', 'El flow debe tener al menos una pantalla')
    else
      validate_screen_ids(screens)
      screens.each { |screen| validate_screen(screen, screens) }
      validate_terminal_screen(screens)
    end

    { valid: @errors.empty?, errors: @errors }
  end

  private

  def validate_name_and_category
    add_error(nil, nil, 'name', 'El nombre es obligatorio') if @flow.name.blank?
    return if JabvoxWhatsappFlow::CATEGORIES.include?(@flow.category)

    add_error(nil, nil, 'category', "Categoría inválida: #{@flow.category}")
  end

  def validate_screen_ids(screens)
    ids = screens.map { |s| s['id'] || s[:id] }
    ids.each do |id|
      if id.blank?
        add_error(nil, nil, 'id', 'Toda pantalla debe tener un id')
      elsif id.to_s == 'SUCCESS'
        add_error(id, nil, 'id', "'SUCCESS' es un id reservado por Meta y no puede usarse")
      end
    end
    dups = ids.tally.select { |_, count| count > 1 }.keys
    dups.each { |id| add_error(id, nil, 'id', "Id de pantalla duplicado: #{id}") }
  end

  def validate_screen(screen, all_screens)
    screen_id = screen['id'] || screen[:id]
    components = Array(screen['components'] || screen[:components])

    if components.size > Catalog::MAX_COMPONENTS_PER_SCREEN
      add_error(screen_id, nil, 'components',
                "Máximo #{Catalog::MAX_COMPONENTS_PER_SCREEN} componentes por pantalla (tiene #{components.size})")
    end

    validate_component_limits(screen_id, components)
    known_names = component_names(all_screens, upto_screen_id: screen_id)
    components.each { |c| validate_component(screen_id, c, known_names) }
    validate_navigation(screen, screen_id, all_screens)
  end

  def validate_component_limits(screen_id, components)
    components.group_by { |c| c['type'] || c[:type] }.each do |type, list|
      limit = Catalog.per_screen_limit(type)
      next unless limit && list.size > limit

      add_error(screen_id, nil, type, "Máximo #{limit} componente(s) de tipo #{type} por pantalla (tiene #{list.size})")
    end
  end

  def validate_component(screen_id, component, known_names)
    type = (component['type'] || component[:type]).to_s
    component_id = component['id'] || component[:id]
    props = component['props'] || component[:props] || {}

    unless Catalog.known?(type)
      add_error(screen_id, component_id, 'type', "Componente no soportado: #{type}")
      return
    end

    Catalog.required_props(type).each do |field|
      value = props[field] || props[field.to_sym]
      add_error(screen_id, component_id, field, "Campo obligatorio '#{field}' faltante en #{type}") if value.blank?
    end

    validate_options_limit(screen_id, component_id, type, props)
    validate_field_name(screen_id, component_id, props)
    validate_max_lengths(screen_id, component_id, type, props)
    validate_variable_references(screen_id, component_id, props, known_names)
  end

  # El nombre del campo es la clave de la respuesta y va en las referencias
  # ${form.campo}, así que Meta exige que sea un identificador.
  def validate_field_name(screen_id, component_id, props)
    name = props['name'] || props[:name]
    return if name.blank? || name.to_s.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)

    add_error(screen_id, component_id, 'name',
              "Nombre de campo inválido '#{name}': solo letras, números y guion bajo, empezando por una letra")
  end

  def validate_max_lengths(screen_id, component_id, type, props)
    (Catalog::MAX_LENGTHS[type.to_s] || {}).each do |field, limit|
      value = props[field] || props[field.to_sym]
      next unless value.is_a?(String) && value.length > limit

      add_error(screen_id, component_id, field,
                "'#{field}' admite máximo #{limit} caracteres (tiene #{value.length})")
    end
  end

  def validate_options_limit(screen_id, component_id, type, props)
    limit = Catalog.options_limit(type)
    return unless limit

    options = props['data_source'] || props[:data_source]
    return if options.blank?

    return unless options.is_a?(Array) && options.size > limit

    add_error(screen_id, component_id, 'data_source', "Máximo #{limit} opciones para #{type} (tiene #{options.size})")
  end

  # ${screen.X.form.Y} must reference a screen strictly earlier in the flow, and a
  # field name that exists on it — prevents cycles and dangling references (doc 4.4/5.1).
  def validate_variable_references(screen_id, component_id, props, known_names)
    text_blob = props.values.select { |v| v.is_a?(String) }.join(' ')
    text_blob.scan(/\$\{screen\.([a-zA-Z0-9_-]+)\.form\.([a-zA-Z0-9_-]+)\}/).each do |ref_screen_id, ref_field|
      unless known_names.key?(ref_screen_id)
        add_error(screen_id, component_id, 'variable',
                  "Referencia a variable de una pantalla inexistente o posterior: #{ref_screen_id}")
        next
      end
      next if known_names[ref_screen_id].include?(ref_field)

      add_error(screen_id, component_id, 'variable',
                "Referencia a un campo inexistente '#{ref_field}' en la pantalla #{ref_screen_id}")
    end
  end

  # { screen_id => Set of component `name`s } for every screen strictly BEFORE
  # `upto_screen_id` in array order (array order is the flow's declared order,
  # per architecture doc 4.3: "la primera pantalla del array es la pantalla de inicio").
  def component_names(all_screens, upto_screen_id:)
    names = {}
    all_screens.each do |s|
      sid = (s['id'] || s[:id]).to_s
      break if sid == upto_screen_id.to_s

      comps = Array(s['components'] || s[:components])
      names[sid] = comps.filter_map { |c| (c['props'] || c[:props] || {})['name'] || (c['props'] || c[:props] || {})[:name] }.to_set
    end
    names
  end

  def validate_navigation(screen, screen_id, all_screens)
    terminal = screen['terminal'] || screen[:terminal]
    components = Array(screen['components'] || screen[:components])
    footer = components.find { |c| (c['type'] || c[:type]) == 'Footer' }

    if terminal
      validate_terminal_footer(screen_id, footer)
      return
    end

    if footer.blank?
      add_error(screen_id, nil, 'footer', 'Pantalla no terminal sin Footer de navegación')
      return
    end

    action = (footer['props'] || footer[:props] || {})['action'] || (footer['props'] || footer[:props] || {})[:action]
    validate_footer_action(screen_id, action, all_screens)
  end

  def validate_terminal_footer(screen_id, footer)
    if footer.blank?
      add_error(screen_id, nil, 'footer', "Pantalla terminal '#{screen_id}' requiere un Footer con acción 'complete'")
      return
    end

    action = (footer['props'] || footer[:props] || {})['action'] || (footer['props'] || footer[:props] || {})[:action]
    name = action && (action['name'] || action[:name])
    return if name.to_s == 'complete'

    add_error(screen_id, nil, 'footer', "El Footer de la pantalla terminal '#{screen_id}' debe tener acción 'complete'")
  end

  def validate_footer_action(screen_id, action, all_screens)
    if action.blank?
      add_error(screen_id, nil, 'footer.action', 'El Footer debe declarar una acción de navegación')
      return
    end

    name = action['name'] || action[:name]
    return unless name.to_s == 'navigate'

    next_id = action['next'] || action[:next]
    if next_id.blank?
      add_error(screen_id, nil, 'footer.action.next', "Acción 'navigate' sin pantalla destino")
      return
    end

    if next_id.to_s == screen_id.to_s
      add_error(screen_id, nil, 'footer.action.next', 'Una pantalla no puede navegar hacia sí misma')
      return
    end

    known_ids = all_screens.map { |s| (s['id'] || s[:id]).to_s }
    return if known_ids.include?(next_id.to_s)

    add_error(screen_id, nil, 'footer.action.next', "La pantalla destino '#{next_id}' no existe")
  end

  def validate_terminal_screen(screens)
    has_terminal = screens.any? { |s| s['terminal'] || s[:terminal] }
    return if has_terminal

    add_error(nil, nil, 'screens', 'El flow debe tener al menos una pantalla terminal (con Footer de acción complete)')
  end

  def add_error(screen_id, component_id, field, message)
    @errors << { screen_id: screen_id, component_id: component_id, field: field, message: message }
  end
end
