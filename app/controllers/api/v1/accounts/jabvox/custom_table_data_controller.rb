# CRUD for the rows (records) of a STANDALONE custom table — i.e. a table not
# linked to leads/contacts. This is the "fill the table with data" surface.
#
# Security posture:
#   - Feature-gated (jabvox_customization_enabled_jabvox).
#   - Admin-only (custom tables are an account-configuration surface).
#   - Every query is scoped through Current.account, so one account can never
#     read or write another account's tables or rows.
#   - Rejects the system "Leads" table and any lead/contact-linked table here:
#     their rows belong to a lead/contact and are edited from the lead detail,
#     not as free-standing records.
#   - Row data is run through CustomRowDataSanitizer, which drops unknown keys,
#     coerces values to each column's type, and enforces required columns.
class Api::V1::Accounts::Jabvox::CustomTableDataController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_customization_enabled
  before_action :ensure_admin
  before_action :set_table
  before_action :set_row, only: [:update, :destroy]

  # GET /jabvox/custom_tables/:custom_table_id/data
  def index
    rows = @table.jabvox_custom_table_rows.standalone.order(created_at: :asc)
    render json: { table: table_summary, rows: rows.map { |r| row_json(r) } }
  end

  # POST /jabvox/custom_tables/:custom_table_id/data
  def create
    result = sanitize(row_params)
    return render_invalid(result) unless result.valid?

    row = @table.jabvox_custom_table_rows.create!(data_jabvox: result.data)
    render json: row_json(row), status: :created
  end

  # PATCH /jabvox/custom_tables/:custom_table_id/data/:id
  def update
    result = sanitize(row_params)
    return render_invalid(result) unless result.valid?

    @row.update!(data_jabvox: result.data)
    render json: row_json(@row)
  end

  # DELETE /jabvox/custom_tables/:custom_table_id/data/:id
  def destroy
    @row.destroy!
    head :no_content
  end

  private

  def check_customization_enabled
    return if Current.account.jabvox_customization_enabled_jabvox?

    render json: { error: 'Customization module not enabled' }, status: :forbidden
  end

  # Admins keep full access (jabvox_can? bypasses for admins); a custom role may
  # also manage this data via jabvox_custom_data_manage.
  def ensure_admin
    return if jabvox_can?('jabvox_custom_data_manage')

    render json: { error: 'Solo los administradores pueden gestionar datos de tablas' }, status: :forbidden
  end

  # Standalone tables only. Lead-linked and the system Leads table are rejected
  # here — their data is per-lead and lives on the lead detail view.
  def set_table
    @table = Current.account.jabvox_custom_tables.find(params[:custom_table_id])
    return if @table.linked_to_jabvox.blank?

    render json: { error: 'Esta tabla guarda datos por lead/contacto; edítala desde el detalle del lead' },
           status: :unprocessable_entity
  end

  # Scoped to this table's standalone rows so an id from another table/account
  # cannot be targeted.
  def set_row
    @row = @table.jabvox_custom_table_rows.standalone.find(params[:id])
  end

  def sanitize(raw)
    Jabvox::CustomRowDataSanitizer.new(@table, raw).call
  end

  # Accept a free-form hash; the sanitizer is what enforces the schema, so we
  # do not need strong-params key lists here (unknown keys are dropped anyway).
  def row_params
    params.fetch(:data, {}).permit!.to_h
  end

  def render_invalid(result)
    render json: { errors: result.errors }, status: :unprocessable_entity
  end

  def table_summary
    {
      id: @table.id,
      name_jabvox: @table.name_jabvox,
      columns: @table.jabvox_custom_columns.ordered.map do |c|
        {
          id: c.id,
          name_jabvox: c.name_jabvox,
          label_jabvox: c.label_jabvox,
          column_type_jabvox: c.column_type_jabvox,
          options_jabvox: c.options_jabvox,
          required_jabvox: c.required_jabvox,
          position_jabvox: c.position_jabvox
        }
      end
    }
  end

  def row_json(row)
    { id: row.id, data: row.data_jabvox || {}, created_at: row.created_at, updated_at: row.updated_at }
  end
end
