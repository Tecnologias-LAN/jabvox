class Api::V1::Accounts::Jabvox::CustomTableRowsController < Api::V1::Accounts::BaseController
  before_action :check_customization_enabled
  before_action :set_lead

  # GET /jabvox/leads/:lead_id/custom_table_rows
  # Returns the MULTI-row tables (Asesorías, Casos…) with their columns and this
  # lead's rows. The single "Leads" system table is edited via the inline
  # custom_fields endpoint, so it's excluded here.
  def index
    tables = Current.account.jabvox_custom_tables.multi_for_leads.ordered.includes(:jabvox_custom_columns)
    rows_by_table = @lead.jabvox_custom_table_rows.group_by(&:jabvox_custom_table_id)

    render json: tables.map { |table| table_payload(table, rows_by_table[table.id] || []) }
  end

  # POST /jabvox/leads/:lead_id/custom_table_rows/:id  (id = table id)
  # Adds a NEW row to a multi-kind table (e.g. a new asesoría/caso for the lead).
  def create
    table = find_table
    return render_single_table_error unless table.multi?

    result = Jabvox::CustomRowDataSanitizer.new(table, row_params).call
    return render json: { errors: result.errors }, status: :unprocessable_entity unless result.valid?

    row = @lead.jabvox_custom_table_rows.create!(jabvox_custom_table: table, data_jabvox: result.data)
    render json: row_json(row), status: :created
  end

  # PUT /jabvox/leads/:lead_id/custom_table_rows/:id
  # single table: id = table id (upsert the lead's single row).
  # multi table:  id = table id, plus params[:row_id] to edit one specific row.
  def update
    table = find_table
    result = Jabvox::CustomRowDataSanitizer.new(table, row_params).call
    return render json: { errors: result.errors }, status: :unprocessable_entity unless result.valid?

    row = target_row(table)
    # Merge the new answers over the existing ones, then DROP any column now
    # hidden by its condition — so switching a controlling answer (e.g. the
    # acompañamiento) clears the questions from the path no longer taken instead
    # of leaving stale values behind.
    merged = (row.data_jabvox || {}).merge(result.data)
    row.data_jabvox = drop_hidden_answers(table, merged)
    row.save!
    render json: row_json(row)
  end

  # DELETE /jabvox/leads/:lead_id/custom_table_rows/:id?row_id=  (id = table id)
  # Removes one row from a multi-kind table.
  def destroy
    table = find_table
    return render_single_table_error unless table.multi?

    row = @lead.jabvox_custom_table_rows.find_by!(jabvox_custom_table_id: table.id, id: params[:row_id])
    row.destroy!
    head :no_content
  end

  private

  def table_payload(table, rows)
    base = {
      table_id: table.id,
      table_name: table.name_jabvox,
      table_description: table.description_jabvox,
      kind: table.kind_jabvox,
      columns: table.jabvox_custom_columns.map { |col| column_json(col) }
    }
    if table.multi?
      base.merge(rows: rows.sort_by(&:id).map { |r| row_json(r) })
    else
      row = rows.first
      base.merge(row_id: row&.id, data: row&.data_jabvox || {})
    end
  end

  def column_json(col)
    {
      id: col.id,
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

  def row_json(row)
    { table_id: row.jabvox_custom_table_id, row_id: row.id, data: row.data_jabvox || {} }
  end

  # For single tables, upsert the one row; for multi, edit the row named by row_id.
  def target_row(table)
    if table.multi?
      @lead.jabvox_custom_table_rows.find_by!(jabvox_custom_table_id: table.id, id: params[:row_id])
    else
      @lead.jabvox_custom_table_rows.find_or_initialize_by(jabvox_custom_table: table)
    end
  end

  def find_table
    Current.account.jabvox_custom_tables.find(params[:id])
  end

  # Removes answers for columns whose condition is not met by the given data, so
  # no stale value survives from a branch the user switched away from.
  def drop_hidden_answers(table, data)
    table.jabvox_custom_columns.each do |column|
      data.delete(column.name_jabvox) unless column.visible_for?(data)
    end
    data
  end

  def render_single_table_error
    render json: { error: 'Esta operación solo aplica a tablas de múltiples registros' },
           status: :unprocessable_entity
  end

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
