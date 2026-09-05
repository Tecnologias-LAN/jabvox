# frozen_string_literal: true

# El voice broadcast pasa a poder FILTRAR sus propios leads (como el dialer) en vez de
# depender de una campaña del dialer ya creada. Añade las columnas de filtro equivalentes
# y hace opcional la referencia a la campaña del dialer (una campaña de voz puede apuntar
# directamente a leads filtrados). El motor de marcado no cambia: solo cambia de dónde
# salen los destinatarios.
class AddLeadFiltersToVoiceBroadcasts < ActiveRecord::Migration[7.1]
  def up
    change_table :jabvox_voice_broadcasts, bulk: true do |t|
      t.jsonb :countries_jabvox
      t.jsonb :management_state_ids_jabvox
      t.jsonb :affiliate_ids_jabvox
      t.jsonb :inbox_ids_jabvox
      t.jsonb :excluded_lead_ids_jabvox, null: false, default: []
      t.jsonb :lead_filters_jabvox, null: false, default: {}
      t.bigint :jabvox_campaign_id # campaña de leads (no la del dialer), como el dialer
      # 'campaign' = leads de una campaña del dialer (compat); 'leads' = leads filtrados aquí.
      t.string :source_jabvox, null: false, default: 'campaign'
    end

    # La campaña del dialer deja de ser obligatoria (ahora puede filtrar leads directamente).
    change_column_null :jabvox_voice_broadcasts, :jabvox_dialer_campaign_id, true
  end

  def down
    change_table :jabvox_voice_broadcasts, bulk: true do |t|
      t.remove :countries_jabvox, :management_state_ids_jabvox, :affiliate_ids_jabvox,
               :inbox_ids_jabvox, :excluded_lead_ids_jabvox, :lead_filters_jabvox,
               :jabvox_campaign_id, :source_jabvox
    end
  end
end
