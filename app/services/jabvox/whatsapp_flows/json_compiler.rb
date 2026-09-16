# Pure compiler: screens_json (Jabvox's internal builder format, architecture doc
# section 4.3) -> Flow JSON 7.3 as Meta expects it (section 2.2). No I/O. Reused both
# for the read-only JSON preview tab and for the real publish (PublishService).
#
# Screens without an endpoint (the only kind this v1 supports, doc section 2.4) never
# set routing_model/data_channel_uri — Meta infers routing from the navigate actions.
class Jabvox::WhatsappFlows::JsonCompiler
  FLOW_JSON_VERSION = '7.3'.freeze

  def initialize(flow_or_screens)
    @screens = flow_or_screens.respond_to?(:screens_json) ? flow_or_screens.screens_json : flow_or_screens
  end

  def call
    {
      version: FLOW_JSON_VERSION,
      screens: Array(@screens).sort_by { |s| s['order'] || s[:order] || 0 }.map { |s| compile_screen(s) }
    }
  end

  private

  def compile_screen(screen)
    {
      id: screen['id'] || screen[:id],
      title: screen['title'] || screen[:title],
      terminal: !!(screen['terminal'] || screen[:terminal]),
      data: screen['data'] || screen[:data] || {},
      layout: {
        type: 'SingleColumnLayout',
        children: Array(screen['components'] || screen[:components]).map { |c| compile_component(c) }
      }
    }.compact
  end

  def compile_component(component)
    type = component['type'] || component[:type]
    props = component['props'] || component[:props] || {}

    { type: type }.merge(compile_props(type, props))
  end

  # snake_case builder keys -> kebab-case Meta keys, via the shared catalog map
  # (Jabvox::WhatsappFlows::ComponentCatalog::PROP_KEY_MAP), so this stays in sync
  # with whatever Validator also treats as a known prop.
  #
  # `action` is handled separately: Meta has no generic "action" key on a component —
  # Footer/EmbeddedLink emit on-click-action, selection components emit
  # on-select-action, per ComponentCatalog.action_prop_key. A component type with no
  # mapped action key (e.g. a stray `action` prop on a text component) simply drops it.
  def compile_props(type, props)
    props.each_with_object({}) do |(key, value), out|
      if key.to_s == 'action'
        meta_key = Jabvox::WhatsappFlows::ComponentCatalog.action_prop_key(type)
        out[meta_key.to_sym] = compile_value(value) if meta_key
        next
      end

      meta_key = Jabvox::WhatsappFlows::ComponentCatalog.meta_prop_key(key)
      out[meta_key.to_sym] = compile_value(value)
    end
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
