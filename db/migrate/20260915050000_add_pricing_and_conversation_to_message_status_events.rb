class AddPricingAndConversationToMessageStatusEvents < ActiveRecord::Migration[7.1]
  def change
    # Datos que Meta ya entrega en el webhook de status y que hasta ahora se
    # descartaban. Sin ellos no se puede reportar costo real por plantilla ni
    # distinguir conversaciones iniciadas por el negocio de las del usuario.
    # Ver docs/whatsapp-flows/templates-sending-architecture.md sección 4.
    add_column :message_status_events, :pricing_category, :string
    # Tri-estado a propósito (sin default ni NOT NULL): nil = Meta no informó
    # pricing en ese status (los no facturables no lo traen), distinto de
    # false = informado explícitamente como no facturable.
    add_column :message_status_events, :pricing_billable, :boolean # rubocop:disable Rails/ThreeStateBooleanColumn
    add_column :message_status_events, :pricing_model, :string
    add_column :message_status_events, :whatsapp_conversation_id, :string
    add_column :message_status_events, :conversation_origin_type, :string

    # Para agregar costo por categoría en el reporte de plantillas sin escanear
    # toda la tabla (filtrado siempre por cuenta + ventana de tiempo).
    add_index :message_status_events, [:account_id, :pricing_category],
              name: 'idx_message_status_events_account_pricing'
  end
end
