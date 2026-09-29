# frozen_string_literal: true

# Catálogos que necesita la ficha del contacto para poder editar: los campos personalizados
# que la cuenta tiene configurados y los estados de gestión con sus preguntas.
#
# Está fuera del controlador porque son datos de configuración de la cuenta, no del contacto:
# los mismos catálogos los consume la lista de contactos y, más adelante, cualquier otra
# pantalla que deba tipificar.
class Jabvox::ContactFormCatalog
  def initialize(account)
    @account = account
  end

  # Campos personalizados del contacto, leídos de la tabla personalizada de contactos —la
  # misma que alimenta los filtros de la lista.
  def custom_field_defs
    table = @account.jabvox_custom_tables.for_contacts.first
    return [] unless table

    table.jabvox_custom_columns.ordered.map do |column|
      { key: column.name_jabvox,
        label: column.label_jabvox.presence || column.name_jabvox,
        column_type: column.column_type_jabvox,
        options: Array(column.options_jabvox).map(&:to_s).reject(&:blank?) }
    end
  end

  # Estados de gestión activos con sus preguntas, para el diálogo de "añadir gestión".
  def management_states
    @account.jabvox_management_states.active.ordered.includes(:questions).map do |state|
      state_view(state)
    end
  end

  # Tablas personalizadas de VARIAS filas (Asesorías, Casos…) con las filas del contacto.
  # Cada tabla viaja con sus columnas para que el frontend pueda pintarlas y editarlas sin
  # pedir el esquema por separado.
  def record_tables_for(contact, limit:)
    tables = @account.jabvox_custom_tables.multi_for_contacts.ordered
                     .includes(:jabvox_custom_columns)
    rows_by_table = contact.jabvox_custom_table_rows.group_by(&:jabvox_custom_table_id)

    tables.map { |table| record_table_view(table, rows_by_table[table.id] || [], limit) }
  end

  private

  def record_table_view(table, rows, limit)
    { table_id: table.id, table_name: table.name_jabvox,
      table_description: table.description_jabvox,
      columns: table.jabvox_custom_columns.map { |c| record_column_view(c) },
      rows: rows.sort_by(&:id).reverse.first(limit).map do |row|
        { row_id: row.id, data: row.data_jabvox || {}, created_at: row.created_at }
      end }
  end

  def record_column_view(column)
    { name_jabvox: column.name_jabvox, label_jabvox: column.label_jabvox,
      column_type_jabvox: column.column_type_jabvox, options_jabvox: column.options_jabvox,
      required_jabvox: column.required_jabvox, position_jabvox: column.position_jabvox,
      depends_on_jabvox: column.depends_on_jabvox, show_when_jabvox: column.show_when_jabvox }
  end

  def state_view(state)
    { id: state.id, name_jabvox: state.name_jabvox, state_group_jabvox: state.state_group_jabvox,
      color_jabvox: state.color_jabvox, note_mode: state.note_mode,
      managed_jabvox: state.managed_jabvox, contact_jabvox: state.contact_jabvox,
      effective_contact_jabvox: state.effective_contact_jabvox, advisory_jabvox: state.advisory_jabvox,
      service_type_jabvox: state.service_type_jabvox, positivity_level_jabvox: state.positivity_level_jabvox,
      questions: state.questions.map { |q| question_view(q) } }
  end

  def question_view(question)
    { id: question.id, label: question.label, question_type: question.question_type,
      required: question.required, options: question.options, position: question.position,
      lead_field: question.lead_field, lead_field_locked: question.lead_field_locked,
      visibility: question.visibility }
  end
end
