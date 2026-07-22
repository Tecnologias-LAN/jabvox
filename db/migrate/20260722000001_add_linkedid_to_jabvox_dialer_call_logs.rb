# frozen_string_literal: true

# El dialer guardaba solo uniqueid_jabvox, tomado del evento Hangup que llegara
# primero — pero una llamada tiene varios legs (trunk + agente) con uniqueids
# distintos, así que a veces guardaba uno que NO coincidía con el uniqueid que el
# CDR de Asterisk registra (el del leg del trunk). Resultado: el reporte no
# reconocía la llamada como del dialer y salía como "Manual" con destino "s".
#
# El linkedid es común a TODOS los legs de una misma llamada y es estable; el CDR
# lo trae en su columna linkedid. Guardarlo permite cruzar CDR ↔ call log de forma
# fiable. Índice para que el resolver haga el match por linkedid rápido.
class AddLinkedidToJabvoxDialerCallLogs < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    add_column :jabvox_dialer_call_logs, :linkedid_jabvox, :string
    add_index :jabvox_dialer_call_logs, %i[account_id linkedid_jabvox],
              name: 'idx_dialer_logs_account_linkedid',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
