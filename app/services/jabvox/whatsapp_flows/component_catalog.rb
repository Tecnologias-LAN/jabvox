# Single source of truth for the WhatsApp Flow JSON 7.3 components Jabvox's builder
# supports (architecture doc section 2.3). Both Validator and JsonCompiler read this
# instead of hardcoding the component list in more than one place.
#
# Deliberately excluded (out of scope v1, see architecture doc section 2.3):
# PhotoPicker, DocumentPicker, CalendarPicker, NavigationList, ImageCarousel,
# RichText, If/Switch.
module Jabvox::WhatsappFlows::ComponentCatalog
  # type => { per_screen_limit: Integer or nil (nil = no artificial limit),
  #           required_props: [snake_case prop names the builder must fill in] }
  COMPONENTS = {
    'TextHeading' => { per_screen_limit: nil, required_props: %w[text] },
    'TextSubheading' => { per_screen_limit: nil, required_props: %w[text] },
    'TextBody' => { per_screen_limit: nil, required_props: %w[text] },
    'TextCaption' => { per_screen_limit: nil, required_props: %w[text] },
    'TextInput' => { per_screen_limit: nil, required_props: %w[name label] },
    'TextArea' => { per_screen_limit: nil, required_props: %w[name label] },
    'RadioButtonsGroup' => { per_screen_limit: nil, required_props: %w[name label data_source] },
    'CheckboxGroup' => { per_screen_limit: nil, required_props: %w[name label data_source] },
    'Dropdown' => { per_screen_limit: nil, required_props: %w[name label data_source] },
    'ChipsSelector' => { per_screen_limit: nil, required_props: %w[name label data_source] },
    'DatePicker' => { per_screen_limit: nil, required_props: %w[name label] },
    'OptIn' => { per_screen_limit: 5, required_props: %w[name label] },
    'Image' => { per_screen_limit: 3, required_props: %w[src] },
    'EmbeddedLink' => { per_screen_limit: 2, required_props: %w[text action] },
    'Footer' => { per_screen_limit: 1, required_props: %w[label action] }
  }.freeze

  # Components whose data-source options are capped by Meta.
  OPTIONS_LIMITS = {
    'RadioButtonsGroup' => 20,
    'CheckboxGroup' => 20,
    'Dropdown' => 200,
    'ChipsSelector' => 20
  }.freeze

  MAX_COMPONENTS_PER_SCREEN = 50

  # snake_case builder prop key => kebab-case Meta Flow JSON key. Only entries that
  # actually differ need listing; JsonCompiler falls back to the raw key otherwise.
  #
  # NOTE: 'action' is deliberately NOT listed here — Meta has no generic "action" key.
  # It maps to either on-click-action or on-select-action depending on the component
  # type (see ON_CLICK_ACTION_TYPES/ON_SELECT_ACTION_TYPES below); JsonCompiler must
  # branch on that instead of using this flat map for that one prop.
  PROP_KEY_MAP = {
    'data_source' => 'data-source',
    'input_type' => 'input-type',
    'min_chars' => 'min-chars',
    'max_chars' => 'max-chars',
    'max_length' => 'max-length',
    'init_value' => 'init-value',
    'error_message' => 'error-message',
    'helper_text' => 'helper-text',
    'media_size' => 'media-size',
    'scale_type' => 'scale-type'
  }.freeze

  # Components whose builder `action` prop compiles to Meta's `on-click-action`.
  ON_CLICK_ACTION_TYPES = %w[Footer EmbeddedLink].freeze
  # Components whose builder `action` prop compiles to Meta's `on-select-action`.
  ON_SELECT_ACTION_TYPES = %w[RadioButtonsGroup CheckboxGroup Dropdown ChipsSelector DatePicker].freeze

  TYPES = COMPONENTS.keys.freeze

  def self.known?(type)
    COMPONENTS.key?(type.to_s)
  end

  def self.required_props(type)
    COMPONENTS.dig(type.to_s, :required_props) || []
  end

  def self.per_screen_limit(type)
    COMPONENTS.dig(type.to_s, :per_screen_limit)
  end

  def self.options_limit(type)
    OPTIONS_LIMITS[type.to_s]
  end

  def self.meta_prop_key(snake_case_key)
    PROP_KEY_MAP[snake_case_key.to_s] || snake_case_key.to_s
  end

  # Meta's Flow JSON key for a component's `action` prop, or nil if that component
  # type doesn't support an action at all (compile_props should then drop the prop).
  def self.action_prop_key(type)
    return 'on-click-action' if ON_CLICK_ACTION_TYPES.include?(type.to_s)
    return 'on-select-action' if ON_SELECT_ACTION_TYPES.include?(type.to_s)

    nil
  end
end
