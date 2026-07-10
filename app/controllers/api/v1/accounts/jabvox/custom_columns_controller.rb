class Api::V1::Accounts::Jabvox::CustomColumnsController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_customization_enabled
  before_action :ensure_module_permission
  before_action :set_table
  before_action :set_column, only: [:update, :destroy]

  def index
    render json: @table.jabvox_custom_columns.ordered.map { |c| column_json(c) }
  end

  def create
    @column = @table.jabvox_custom_columns.build(column_params)
    @column.save!
    render json: column_json(@column), status: :created
  end

  def update
    old_name = @column.name_jabvox
    @column.update!(column_params)
    migrate_stored_key(old_name, @column.name_jabvox) if @column.name_jabvox != old_name
    render json: column_json(@column)
  end

  def destroy
    @column.destroy!
    purge_stored_key(@column.name_jabvox)
    head :no_content
  end

  private

  def check_customization_enabled
    return if Current.account.jabvox_customization_enabled_jabvox?

    render json: { error: 'Customization module not enabled' }, status: :forbidden
  end

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_custom_data_manage')
  end

  def set_table
    @table = Current.account.jabvox_custom_tables.find(params[:custom_table_id])
  end

  def set_column
    @column = @table.jabvox_custom_columns.find(params[:id])
  end

  # Values live in jsonb payloads (row data_jabvox and, for lead-linked
  # tables, jabvox_leads.custom_fields_jabvox). Definitions and stored values
  # only stay consistent if keys are pruned/renamed alongside the column;
  # otherwise every lead keeps orphaned keys forever.
  # rubocop:disable Rails/SkipsModelValidations
  def purge_stored_key(key)
    @table.jabvox_custom_table_rows
          .where('jsonb_exists(data_jabvox, :key)', key: key)
          .update_all(['data_jabvox = data_jabvox - :key', { key: key }])
    return unless @table.linked_to_jabvox == 'leads'

    Current.account.jabvox_leads
           .where('jsonb_exists(custom_fields_jabvox, :key)', key: key)
           .update_all(['custom_fields_jabvox = custom_fields_jabvox - :key', { key: key }])
  end

  def migrate_stored_key(old_key, new_key)
    @table.jabvox_custom_table_rows
          .where('jsonb_exists(data_jabvox, :old)', old: old_key)
          .update_all(['data_jabvox = (data_jabvox - :old) || jsonb_build_object(:new, data_jabvox -> :old)',
                       { old: old_key, new: new_key }])
    return unless @table.linked_to_jabvox == 'leads'

    Current.account.jabvox_leads
           .where('jsonb_exists(custom_fields_jabvox, :old)', old: old_key)
           .update_all(['custom_fields_jabvox = (custom_fields_jabvox - :old) || ' \
                        'jsonb_build_object(:new, custom_fields_jabvox -> :old)',
                        { old: old_key, new: new_key }])
  end
  # rubocop:enable Rails/SkipsModelValidations

  def column_params
    params.require(:column).permit(
      :name_jabvox, :label_jabvox, :column_type_jabvox,
      :required_jabvox, :position_jabvox,
      options_jabvox: []
    )
  end

  def column_json(col)
    {
      id: col.id,
      jabvox_custom_table_id: col.jabvox_custom_table_id,
      name_jabvox: col.name_jabvox,
      label_jabvox: col.label_jabvox,
      column_type_jabvox: col.column_type_jabvox,
      options_jabvox: col.options_jabvox,
      required_jabvox: col.required_jabvox,
      position_jabvox: col.position_jabvox
    }
  end
end
