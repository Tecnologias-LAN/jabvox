# frozen_string_literal: true

# Presencia en vivo del softphone (heartbeat desde el navegador) + quién colgó la llamada.
#
# El estado por extensión ya NO se consulta por AMI (restringido por IP y da falsos
# UNREACHABLE en WebRTC): ahora el propio softphone reporta su estado al backend y el
# super admin lo lee de aquí. Funciona en dev y producción, para chan_sip y PJSIP.
class AddSoftphonePresenceAndEndedBy < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_softphone_extensions, bulk: true do |t|
      # Estado reportado por el navegador: disconnected/registering/registered/
      # calling/in_call/failed. Es la fuente de verdad de la presencia en vivo.
      t.string :live_state, default: 'disconnected', null: false
      t.datetime :last_seen_at          # último heartbeat recibido
      t.string :last_error              # último motivo de fallo reportado (register_rejected_403…)
      t.string :remote_ip               # IP pública del navegador (diagnóstico)
      t.string :user_agent_info         # navegador/SO (diagnóstico)
    end
    add_index :jabvox_softphone_extensions, :last_seen_at

    # Quién terminó la llamada: 'agent' (el usuario del softphone) o 'remote' (el otro lado).
    add_column :jabvox_softphone_call_logs, :ended_by, :string
  end
end
