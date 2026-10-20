# Importa un catálogo de tipificaciones con sus infaltables a una cuenta, en
# bloque y de forma idempotente. Pensado para arrancar una cuenta a partir de un
# documento de QA (como "Infaltables con guión"), pero sirve para cualquier
# empresa: recibe una estructura neutra, no datos de LikeU hardcodeados.
#
# Formato de entrada (array):
#   [{ "typification" => "Correteo · ...", "infaltables" => [
#        { "text" => "...", "optional" => false }, ... ] }, ... ]
#
# - Crea la tipificación si no existe (match por nombre, case-insensitive).
# - Reemplaza los infaltables de audio de esa tipificación (no acumula duplicados
#   al re-importar).
class Jabvox::AudioInfaltablesImporterService
  # Cotas defensivas para una importación en bloque.
  MAX_TYPIFICATIONS = 200
  MAX_INFALTABLES_PER_TYPIFICATION = 100

  def initialize(account, created_by: nil)
    @account = account
    @created_by = created_by
  end

  # Devuelve un resumen { typifications:, infaltables: } con los conteos creados.
  def import(entries)
    typ_count = 0
    inf_count = 0

    ActiveRecord::Base.transaction do
      Array(entries).first(MAX_TYPIFICATIONS).each do |entry|
        name = entry['typification'].to_s.strip
        items = Array(entry['infaltables']).first(MAX_INFALTABLES_PER_TYPIFICATION)
        next if name.blank? || items.empty?

        typification = find_or_create_typification(name)
        typ_count += 1
        inf_count += replace_infaltables(typification, items)
      end
    end

    { typifications: typ_count, infaltables: inf_count }
  end

  private

  def find_or_create_typification(name)
    existing = @account.jabvox_typifications.where('LOWER(name) = ?', name.downcase).first
    return existing if existing

    @account.jabvox_typifications.create!(name: name.first(150), created_by: @created_by)
  end

  def replace_infaltables(typification, items)
    typification.audio_infaltables.delete_all
    items.each_with_index do |item, i|
      text = item['text'].to_s.strip
      next if text.blank?

      typification.audio_infaltables.create!(
        account: @account, created_by: @created_by, position: i,
        text: text.first(2000),
        optional: ActiveModel::Type::Boolean.new.cast(item['optional']) || false
      )
    end
    typification.audio_infaltables.count
  end
end
