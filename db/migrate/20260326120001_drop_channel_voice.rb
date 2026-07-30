class DropChannelVoice < ActiveRecord::Migration[7.0]
  def up
    return unless table_exists?(:channel_voice)

    # Seguridad: upstream reemplazó channel_voice por `calls`. Solo se borra si
    # está vacía; si tuviera datos, abortamos para revisarlos antes de perderlos.
    count = select_value('SELECT COUNT(*) FROM channel_voice').to_i
    if count.positive?
      raise "channel_voice tiene #{count} fila(s); no se borra automáticamente. " \
            'Migra o respalda esos datos y vuelve a intentar (la voz ahora vive en la tabla `calls`).'
    end

    drop_table :channel_voice, if_exists: true
  end

  def down
    create_table :channel_voice do |t|
      t.string :phone_number, null: false
      t.string :provider, null: false, default: 'twilio'
      t.jsonb :provider_config, null: false
      t.integer :account_id, null: false
      t.jsonb :additional_attributes, default: {}

      t.timestamps
    end

    add_index :channel_voice, :phone_number, unique: true
    add_index :channel_voice, :account_id
  end
end
