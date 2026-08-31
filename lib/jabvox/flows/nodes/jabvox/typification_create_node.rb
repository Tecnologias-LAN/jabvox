# frozen_string_literal: true

# jabvox.typification.create — crea una tipificación en el catálogo de la cuenta.
#
# El nombre es ÚNICO por cuenta: si ya existe NO se falla (un flujo que corre a
# diario no debe romperse por eso) y se devuelve la existente con
# `created: false`, sin pisar su descripción ni reactivarla.
class Jabvox::Flows::Nodes::Jabvox::TypificationCreateNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.typification.create'
  label 'Crear tipificación'

  def perform
    name = param(:name).to_s.strip
    fail_with!('Falta el "Nombre" de la tipificación: escríbelo en el paso.') if name.blank?

    existing = account.jabvox_typifications.find_by(name: name)
    return output(existing, created: false) if existing

    output(create_typification(name), created: true)
  end

  private

  def create_typification(name)
    account.jabvox_typifications.create!(
      name: name, description: first_filled(param(:description)),
      # OPT-OUT: la clave ausente en flujos antiguos deja la tipificación activa.
      is_active: opt_out?(param(:is_active))
    )
  rescue ActiveRecord::RecordInvalid => e
    fail_with!("No se pudo crear la tipificación «#{name}»: #{e.record.errors.full_messages.join(', ')}.")
  end

  def output(typification, created:)
    { 'id' => typification.id, 'name' => typification.name,
      'description' => typification.description, 'is_active' => typification.is_active,
      'created' => created, 'created_at' => typification.created_at.iso8601 }
  end
end
