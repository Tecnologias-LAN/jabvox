require 'administrate/base_dashboard'

class JabvoxDeletedLeadDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    account: Field::BelongsTo,
    original_lead_id_jabvox: Field::Number,
    source_name_jabvox: Field::String,
    external_id_jabvox: Field::String,
    deleted_at_jabvox: Field::DateTime,
    restored_at_jabvox: Field::DateTime,
    snapshot_jabvox: Field::String.with_options(searchable: false),
    created_at: Field::DateTime
  }.freeze

  COLLECTION_ATTRIBUTES = %i[
    id
    account
    source_name_jabvox
    external_id_jabvox
    deleted_at_jabvox
    restored_at_jabvox
  ].freeze

  SHOW_PAGE_ATTRIBUTES = %i[
    id
    account
    original_lead_id_jabvox
    source_name_jabvox
    external_id_jabvox
    snapshot_jabvox
    deleted_at_jabvox
    restored_at_jabvox
    created_at
  ].freeze

  FORM_ATTRIBUTES = [].freeze

  COLLECTION_FILTERS = {}.freeze
end
