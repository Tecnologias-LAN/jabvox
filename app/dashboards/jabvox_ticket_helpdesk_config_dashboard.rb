require 'administrate/base_dashboard'

class JabvoxTicketHelpdeskConfigDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    auto_assign_mode_jabvox: Field::Select.with_options(
      collection: JabvoxTicketHelpdeskConfig.auto_assign_mode_jabvoxes.keys
    ),
    resolver_visibility_jabvox: Field::Select.with_options(
      collection: JabvoxTicketHelpdeskConfig.resolver_visibility_jabvoxes.keys
    ),
    active_jabvox: Field::Boolean,
    settings_jabvox: Field::String.with_options(searchable: false),
    created_at: Field::DateTime,
    updated_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    auto_assign_mode_jabvox
    active_jabvox
    created_at
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    auto_assign_mode_jabvox
    resolver_visibility_jabvox
    active_jabvox
    created_at
    updated_at
  ].freeze

  FORM_ATTRIBUTES = %i[
    account
    auto_assign_mode_jabvox
    resolver_visibility_jabvox
    active_jabvox
  ].freeze

  COLLECTION_FILTERS = {}.freeze
end
