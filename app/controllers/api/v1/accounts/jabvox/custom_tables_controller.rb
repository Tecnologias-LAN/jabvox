class Api::V1::Accounts::Jabvox::CustomTablesController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_customization_enabled
  before_action :ensure_module_permission
  before_action :set_table, only: [:show, :update, :destroy, :export]

  def index
    ensure_leads_table
    @tables = Current.account.jabvox_custom_tables.ordered
                     .includes(:jabvox_custom_columns)
    render json: @tables.map { |t| table_json(t) }
  end

  def show
    render json: table_json(@table)
  end

  def create
    @table = Current.account.jabvox_custom_tables.build(table_params)
    @table.save!
    render json: table_json(@table), status: :created
  end

  def update
    return render_system_table_locked if @table.system_leads_table?

    @table.update!(table_params)
    render json: table_json(@table)
  end

  def destroy
    return render_system_table_locked if @table.system_leads_table?

    @table.destroy!
    head :no_content
  end

  # GET /custom_tables/:id/export
  # Portable JSON of the table definition + columns (no DB ids, no row data), the
  # same shape `import` accepts — export from one account, import in another.
  def export
    render json: export_payload(@table)
  end

  # POST /custom_tables/import  { data: { table: {...}, columns: [...] } }
  # Recreates a table (definition + columns) from an exported JSON. Pure data:
  # nothing is executed; every field goes through a strict whitelist. The system
  # "Leads" table can never be imported over.
  def import
    result = Jabvox::CustomTableImportService.new(Current.account, import_payload).call
    if result.valid?
      render json: {
        table: table_json(result.table),
        created_columns: result.created_columns,
        updated_columns: result.updated_columns
      }
    else
      render json: { errors: result.errors }, status: :unprocessable_entity
    end
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

  # The "Leads" table is a fixed system table that always exists and cannot be
  # renamed or deleted. Its columns are the lead's custom fields.
  def ensure_leads_table
    return if Current.account.jabvox_custom_tables.exists?(linked_to_jabvox: 'contacts')

    Current.account.jabvox_custom_tables.create!(
      name_jabvox: 'Contactos', description_jabvox: nil, linked_to_jabvox: 'contacts'
    )
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    nil # created concurrently — fine
  end

  def render_system_table_locked
    render json: { error: 'La tabla Leads es del sistema y no se puede editar ni eliminar' }, status: :forbidden
  end

  def set_table
    @table = Current.account.jabvox_custom_tables.find(params[:id])
  end

  def table_params
    params.require(:table).permit(:name_jabvox, :description_jabvox, :position_jabvox, :linked_to_jabvox, :kind_jabvox)
  end

  def table_json(table)
    is_leads = table.system_leads_table?
    {
      id: table.id,
      name_jabvox: is_leads ? 'Leads' : table.name_jabvox,
      description_jabvox: table.description_jabvox,
      position_jabvox: table.position_jabvox,
      linked_to_jabvox: table.linked_to_jabvox,
      kind_jabvox: table.kind_jabvox,
      system: is_leads,
      columns: table.jabvox_custom_columns.map { |c| column_json(c) },
      created_at: table.created_at
    }
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

  # Portable representation: no DB ids, no account, no rows — just the shape
  # CustomTableImportService reads back.
  def export_payload(table)
    {
      version: 1,
      table: {
        name_jabvox: table.name_jabvox,
        description_jabvox: table.description_jabvox,
        kind_jabvox: table.kind_jabvox
      },
      columns: table.jabvox_custom_columns.ordered.map do |c|
        {
          name_jabvox: c.name_jabvox,
          label_jabvox: c.label_jabvox,
          column_type_jabvox: c.column_type_jabvox,
          options_jabvox: c.options_jabvox,
          required_jabvox: c.required_jabvox,
          depends_on_jabvox: c.depends_on_jabvox,
          show_when_jabvox: c.show_when_jabvox
        }
      end
    }
  end

  # The import file arrives under `data` (parsed client-side from the uploaded
  # JSON). permit! is safe: the service whitelists every field itself.
  def import_payload
    raw = params[:data]
    raw = raw.permit!.to_h if raw.respond_to?(:permit!)
    raw.is_a?(Hash) ? raw : {}
  end
end
