# frozen_string_literal: true

# Panel Super Admin: CRUD de planes. Los campos JSON (modules, chatwoot_features, limits)
# se editan como texto JSON en el formulario y se parsean aquí antes de persistir.
class SuperAdmin::JabvoxPlansController < SuperAdmin::ApplicationController
  JSON_ATTRS = %w[modules chatwoot_features limits].freeze

  def resource_params
    permitted = params.require(resource_class.model_name.param_key)
                      .permit(dashboard.permitted_attributes)
    JSON_ATTRS.each do |attr|
      next unless permitted.key?(attr)

      permitted[attr] = parse_json(permitted[attr], attr)
    end
    permitted
  end

  private

  # Acepta JSON válido; si viene vacío usa el default correcto (array u objeto).
  def parse_json(value, attr)
    return default_for(attr) if value.blank?
    return value unless value.is_a?(String)

    JSON.parse(value)
  rescue JSON::ParserError
    default_for(attr)
  end

  def default_for(attr)
    attr == 'limits' ? {} : []
  end
end
