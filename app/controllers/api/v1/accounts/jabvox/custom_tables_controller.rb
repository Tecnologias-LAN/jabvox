class Api::V1::Accounts::Jabvox::CustomTablesController < Api::V1::Accounts::BaseController
  before_action :check_customization_enabled
  before_action :set_table, only: [:show, :update, :destroy]

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
    return render_system_table_locked if @table.linked_to_jabvox == 'leads'

    @table.update!(table_params)
    render json: table_json(@table)
  end

  def destroy
    return render_system_table_locked if @table.linked_to_jabvox == 'leads'

    @table.destroy!
    head :no_content
  end

  private

  def check_customization_enabled
    return if Current.account.jabvox_customization_enabled_jabvox?

    render json: { error: 'Customization module not enabled' }, status: :forbidden
  end

  # The "Leads" table is a fixed system table that always exists and cannot be
  # renamed or deleted. Its columns are the lead's custom fields.
  def ensure_leads_table
    return if Current.account.jabvox_custom_tables.exists?(linked_to_jabvox: 'leads')

    Current.account.jabvox_custom_tables.create!(
      name_jabvox: 'Leads', description_jabvox: nil, linked_to_jabvox: 'leads'
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
    params.require(:table).permit(:name_jabvox, :description_jabvox, :position_jabvox, :linked_to_jabvox)
  end

  def table_json(table)
    is_leads = table.linked_to_jabvox == 'leads'
    {
      id: table.id,
      name_jabvox: is_leads ? 'Leads' : table.name_jabvox,
      description_jabvox: table.description_jabvox,
      position_jabvox: table.position_jabvox,
      linked_to_jabvox: table.linked_to_jabvox,
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
      position_jabvox: col.position_jabvox
    }
  end
end
