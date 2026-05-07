require 'administrate/base_dashboard'

class JabvoxResponseBotRoleDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    name_jabvox: Field::String,
    prompt_jabvox: Field::Text,
    active_jabvox: Field::Boolean,
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    name_jabvox
    active_jabvox
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    name_jabvox
    prompt_jabvox
    active_jabvox
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    name_jabvox
    prompt_jabvox
    active_jabvox
  ].freeze

  COLLECTION_FILTERS = {}.freeze
end
