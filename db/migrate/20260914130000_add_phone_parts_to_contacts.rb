# frozen_string_literal: true

# El teléfono de un contacto se guarda en TRES piezas, para que cada pantalla use
# la que necesita sin volver a parsear nada:
#
#   phone_country_code_jabvox -> "+57"           (prefijo, sale del país elegido)
#   phone_national_jabvox     -> "3001234567"    (número local, como lo teclea el usuario)
#   phone_number              -> "+573001234567" (E.164, ya existente; es la identidad)
#
# phone_number sigue siendo la columna de identidad y deduplicación (tiene índice
# único y es lo que usa todo Chatwoot); las otras dos son derivadas y se
# recalculan solas al guardar.
#
# OJO: la columna `country_code` de upstream NO sirve para esto — Chatwoot la usa
# para el país ISO tomado de additional_attributes['country'] y la reescribe en
# cada guardado (Contacts::SyncAttributes). Por eso el prefijo va en columna propia.
class AddPhonePartsToContacts < ActiveRecord::Migration[7.1]
  def up
    add_column :contacts, :phone_country_code_jabvox, :string
    add_column :contacts, :phone_national_jabvox, :string

    # Backfill: solo toca filas con un E.164 válido y sin las partes calculadas.
    # Se hace por lotes para no bloquear la tabla en instalaciones grandes.
    say_with_time 'Rellenando las partes del teléfono de los contactos existentes' do
      Contact.reset_column_information
      Contact.where.not(phone_number: [nil, '']).in_batches(of: 1_000) do |batch|
        batch.each { |contact| backfill(contact) }
      end
    end
  end

  def down
    remove_column :contacts, :phone_national_jabvox
    remove_column :contacts, :phone_country_code_jabvox
  end

  private

  def backfill(contact)
    parts = Jabvox::PhoneParts.split(contact.phone_number)
    return if parts.nil?

    # update_columns: no dispara validaciones ni callbacks (una migración no debe
    # ejecutar la lógica de la app sobre datos históricos).
    contact.update_columns( # rubocop:disable Rails/SkipsModelValidations
      phone_country_code_jabvox: parts[:country_code],
      phone_national_jabvox: parts[:national]
    )
  rescue StandardError => e
    Rails.logger.warn("[AddPhonePartsToContacts] contacto=#{contact.id}: #{e.message}")
  end
end
