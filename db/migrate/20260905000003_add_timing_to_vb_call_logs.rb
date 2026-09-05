# frozen_string_literal: true

# Métricas de tiempo por llamada del Voice Broadcast, para el reporte detallado:
#   answered_at        — instante en que la persona contestó (Newstate Up).
#   ring_ms            — cuánto tardó en contestar (desde el originate hasta el answer).
#   total_duration_ms  — duración TOTAL de la llamada (ring + conversación), del hangup.
# (duration_ms_jabvox ya guarda el billsec = tiempo de conversación / audio reproducido.)
class AddTimingToVbCallLogs < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_voice_broadcast_call_logs, :answered_at_jabvox, :datetime
    add_column :jabvox_voice_broadcast_call_logs, :ring_ms_jabvox, :integer
    add_column :jabvox_voice_broadcast_call_logs, :total_duration_ms_jabvox, :integer
    # También en recipients, para reflejar el último intento sin re-consultar los logs.
    add_column :jabvox_voice_broadcast_recipients, :answered_at_jabvox, :datetime
    add_column :jabvox_voice_broadcast_recipients, :ring_ms_jabvox, :integer
  end
end
