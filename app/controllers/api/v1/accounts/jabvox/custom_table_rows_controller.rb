class Api::V1::Accounts::Jabvox::CustomTableRowsController < Api::V1::Accounts::BaseController
  before_action :check_customization_enabled
  before_action :set_lead

  # GET /jabvox/leads/:lead_id/custom_table_rows
  # Returns all tables with their columns + the row data for this lead
  def index
    tables = Current.account.jabvox_custom_tables.ordered.includes(:jabvox_custom_columns)
    rows = @lead.jabvox_custom_table_rows.index_by(&:jabvox_custom_table_id)

    render json: tables.map { |table|
      row = rows[table.id]
      {
        table_id: table.id,
        table_name: table.name_jabvox,
        table_description: table.description_jabvox,
        columns: table.jabvox_custom_columns.map { |col|
          {
            id: col.id,
            name_jabvox: col.name_jabvox,
            label_jabvox: col.label_jabvox,
            column_type_jabvox: col.column_type_jabvox,
            options_jabvox: col.options_jabvox,
            required_jabvox: col.required_jabvox
          }
        },
        row_id: row&.id,
        data: row&.data_jabvox || {}
      }
    }
  end

  # PUT /jabvox/leads/:lead_id/custom_table_rows/:table_id
  # Upserts the row for a specific table. Incoming data is sanitized against the
  # table's columns (unknown keys dropped, values coerced to their type) before
  # being merged into the row's JSONB payload.
  def update
    table = Current.account.jabvox_custom_tables.find(params[:id])
    result = Jabvox::CustomRowDataSanitizer.new(table, row_params).call
    return render json: { errors: result.errors }, status: :unprocessable_entity unless result.valid?

    row = @lead.jabvox_custom_table_rows.find_or_initialize_by(jabvox_custom_table: table)
    row.data_jabvox = (row.data_jabvox || {}).merge(result.data)
    row.save!
    render json: { table_id: table.id, row_id: row.id, data: row.data_jabvox }
  end

  private

  def check_customization_enabled
    return if Current.account.jabvox_customization_enabled_jabvox?

    render json: { error: 'Customization module not enabled' }, status: :forbidden
  end

  def set_lead
    @lead = Current.account.jabvox_leads.find(params[:lead_id])
  end

  def row_params
    params.fetch(:data, {}).permit!.to_h
  end
end
