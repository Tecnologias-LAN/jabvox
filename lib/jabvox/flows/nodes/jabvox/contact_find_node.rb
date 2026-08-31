# frozen_string_literal: true

# jabvox.contact.find — busca contactos por nombre, email o teléfono. Devuelve
# `{ count, contacts }` para poder encadenar un bucle sobre la colección.
class Jabvox::Flows::Nodes::Jabvox::ContactFindNode < Jabvox::Flows::Nodes::Jabvox::Base
  type 'jabvox.contact.find'
  label 'Buscar contactos'
  items_path 'contacts'

  DEFAULT_LIMIT = 50
  MAX_LIMIT = 500

  def perform
    query = param(:q).to_s.strip
    fail_with!('Escribe el texto a buscar (nombre, email o teléfono).') if query.blank?

    limit = int_or(param(:limit), DEFAULT_LIMIT, min: 1, max: MAX_LIMIT)
    rows = search(query, limit)
    { 'q' => query, 'count' => rows.length, 'limit' => limit,
      # Con tantas filas como el tope hay contactos sin ver: decirlo evita que
      # el flujo parezca haber terminado su trabajo.
      'truncated' => rows.length >= limit,
      'contacts' => rows.map { |c| contact_view(c).merge('contactId' => c.id) } }
  end

  private

  def search(query, limit)
    pattern = "%#{ActiveRecord::Base.sanitize_sql_like(query)}%"
    account.contacts
           .where('name ILIKE :q OR email ILIKE :q OR phone_number ILIKE :q OR identifier ILIKE :q', q: pattern)
           .order(id: :desc).limit(limit).to_a
  end
end
