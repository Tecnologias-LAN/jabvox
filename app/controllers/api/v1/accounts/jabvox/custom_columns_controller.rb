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
    if @column.name_jabvox != old_name
      migrate_stored_key(old_name, @column.name_jabvox)
      migrate_campaign_filter_key(old_name, @column.name_jabvox)
    end
    render json: column_json(@column)
  end

  def destroy
    @column.destroy!
    purge_stored_key(@column.name_jabvox)
    purge_campaign_filter_key(@column.name_jabvox)
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

  # Los valores viven en jsonb (data_jabvox de cada fila y, en la tabla ligada a contactos,
  # contacts.custom_fields_jabvox). Definición y valores solo siguen coherentes si la clave se
  # borra/renombra junto con la columna; si no, cada contacto conserva claves huérfanas.
  # rubocop:disable Rails/SkipsModelValidations
  def purge_stored_key(key)
    @table.jabvox_custom_table_rows
          .where('jsonb_exists(data_jabvox, :key)', key: key)
          .update_all(['data_jabvox = data_jabvox - :key', { key: key }])
    return unless @table.linked_to_jabvox == 'contacts'

    Current.account.contacts
           .where('jsonb_exists(custom_fields_jabvox, :key)', key: key)
           .update_all(['custom_fields_jabvox = custom_fields_jabvox - :key', { key: key }])
  end

  def migrate_stored_key(old_key, new_key)
    @table.jabvox_custom_table_rows
          .where('jsonb_exists(data_jabvox, :old)', old: old_key)
          .update_all(['data_jabvox = (data_jabvox - :old) || jsonb_build_object(:new, data_jabvox -> :old)',
                       { old: old_key, new: new_key }])
    return unless @table.linked_to_jabvox == 'contacts'

    Current.account.contacts
           .where('jsonb_exists(custom_fields_jabvox, :old)', old: old_key)
           .update_all(['custom_fields_jabvox = (custom_fields_jabvox - :old) || ' \
                        'jsonb_build_object(:new, custom_fields_jabvox -> :old)',
                        { old: old_key, new: new_key }])
  end
  # rubocop:enable Rails/SkipsModelValidations

  # Dialer campaigns persist lead filters by field KEY (lead_filters_jabvox
  # -> custom). Renaming/deleting a lead column must follow through, or the
  # saved campaigns keep filtering by a key that no longer holds data.
  def migrate_campaign_filter_key(old_key, new_key)
    each_campaign_with_filter_key(old_key) do |campaign, custom|
      custom[new_key] = custom.delete(old_key)
      campaign.update_column(:lead_filters_jabvox, campaign.lead_filters_jabvox.merge('custom' => custom)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def purge_campaign_filter_key(key)
    each_campaign_with_filter_key(key) do |campaign, custom|
      custom.delete(key)
      campaign.update_column(:lead_filters_jabvox, campaign.lead_filters_jabvox.merge('custom' => custom)) # rubocop:disable Rails/SkipsModelValidations
    end
  end

  def each_campaign_with_filter_key(key)
    return unless @table.linked_to_jabvox == 'contacts'

    Current.account.jabvox_dialer_campaigns.find_each do |campaign|
      custom = (campaign.lead_filters_jabvox || {})['custom']
      next unless custom.is_a?(Hash) && custom.key?(key)

      yield campaign, custom.dup
    end
  end

  def column_params
    params.require(:column).permit(
      :name_jabvox, :label_jabvox, :column_type_jabvox,
      :required_jabvox, :position_jabvox, :depends_on_jabvox,
      options_jabvox: [], show_when_jabvox: []
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
      position_jabvox: col.position_jabvox,
      depends_on_jabvox: col.depends_on_jabvox,
      show_when_jabvox: col.show_when_jabvox
    }
  end
end
