# Patrón configurable para parsear el nombre de un archivo de audio y extraer de
# él los campos de la llamada. El usuario define una plantilla con marcadores
# {campo} y el parser construye una expresión regular que captura cada campo.
#
# Ejemplos de `pattern`:
#   "{phone}-{campaign} {advisor_name}"            → "3002490237-AMP Paula Ramírez"
#   "{advisor_id}-{typification_id}-{date}-{call_id}" → "01-05-2026-7890"
#
# Campos reconocidos (todos opcionales en una plantilla concreta):
#   phone, advisor_id, advisor_name, typification_id, typification_name,
#   date, call_id, campaign.
#
# El motor de vinculación (Jabvox::Audio::FilenameParser) toma el resultado de
# este parseo y resuelve el asesor y la tipificación reales.
# == Schema Information
#
# Table name: jabvox_audio_filename_patterns
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  date_format   :string           default("%d-%m-%Y"), not null
#  name          :string           not null
#  pattern       :string           not null
#  position      :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_jabvox_audio_filename_patterns_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxAudioFilenamePattern < ApplicationRecord
  self.table_name = 'jabvox_audio_filename_patterns'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  # Campos que una plantilla puede capturar. El orden no importa.
  KNOWN_FIELDS = %w[
    phone advisor_id advisor_name typification_id typification_name
    date call_id campaign
  ].freeze

  # Un token {campo} en la plantilla.
  TOKEN_RE = /\{([a-z_]+)\}/

  validates :name, presence: true, length: { maximum: 150 }
  validates :pattern, presence: true, length: { maximum: 500 }
  validate :pattern_uses_known_fields

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # Lista de campos {…} declarados en la plantilla, en orden de aparición.
  def fields
    pattern.to_s.scan(TOKEN_RE).flatten
  end

  # Intenta parsear un nombre de archivo (sin extensión). Devuelve un hash
  # { campo => valor } si casa, o nil si no. No lanza excepciones: un patrón que
  # no case simplemente devuelve nil para que el parser pruebe el siguiente.
  # Tope defensivo: un nombre de archivo real nunca supera esto; evita trabajo
  # inútil (y cualquier patología de regex) ante un file_key anómalo del bucket.
  MAX_BASENAME = 1024

  def parse(basename)
    name = basename.to_s
    return nil if name.length > MAX_BASENAME

    md = regex.match(name)
    return nil unless md

    fields.each_with_object({}) do |field, acc|
      value = md[field.to_sym]
      acc[field] = value.to_s.strip if value
    end
  rescue RegexpError
    # Regexp::TimeoutError hereda de RegexpError, así que este rescue cubre ambos:
    # un patrón patológico (p. ej. dos capturas de texto adyacentes con un input
    # que no casa) hace backtracking costoso, el timeout del regex lo corta y
    # tratamos el nombre como no parseado, sin colgar el worker.
    nil
  end

  # Construye la regex a partir de la plantilla: el texto literal se escapa y
  # cada {campo} se convierte en un grupo nombrado. Un campo numérico (phone,
  # *_id, call_id, date) captura de forma no-greedy; el resto captura texto.
  def regex
    source = +'\A'
    scanner = pattern.to_s
    last = 0
    scanner.scan(TOKEN_RE) do
      match = Regexp.last_match
      source << Regexp.escape(scanner[last...match.begin(0)])
      field = match[1]
      source << "(?<#{field}>#{capture_for(field)})"
      last = match.end(0)
    end
    source << Regexp.escape(scanner[last..]) if last < scanner.length
    source << '\z'
    # timeout por-regex (Ruby 3.2+): corta cualquier backtracking patológico antes
    # de que bloquee el proceso. 1s es holgado para un nombre de archivo.
    Regexp.new(source, Regexp::IGNORECASE, timeout: 1.0)
  end

  private

  def capture_for(field)
    case field
    when 'phone', 'call_id', 'advisor_id', 'typification_id'
      '[\w.]+?'
    when 'date'
      '[\d\-\/.]+'
    else
      '.+?'
    end
  end

  def pattern_uses_known_fields
    unknown = fields - KNOWN_FIELDS
    return if unknown.empty?

    errors.add(:pattern, "contiene campos no reconocidos: #{unknown.join(', ')}")
  end
end
