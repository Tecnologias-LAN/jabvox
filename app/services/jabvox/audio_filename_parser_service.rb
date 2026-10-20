# Toma el nombre de un archivo de audio y lo resuelve contra los patrones
# configurados de la cuenta para extraer y VINCULAR: asesor, tipificación,
# teléfono, fecha e id de llamada. Devuelve un hash con los campos crudos y los
# objetos resueltos (advisor, typification), sin tocar la base de datos.
#
# No lanza excepciones: si ningún patrón casa, devuelve metadata vacía y deja que
# el llamador use los fallbacks (asignación manual, tipificación del pipeline).
class Jabvox::AudioFilenameParserService
  def initialize(account)
    @account = account
    @patterns = account.jabvox_audio_filename_patterns.active.ordered.to_a
    # Mapeos precargados en memoria (son pocos por cuenta): así resolver cientos de
    # archivos en un job no dispara una query por archivo/campo. Clave en minúsculas.
    mappings = account.jabvox_audio_code_mappings.includes(:typification, :advisor).to_a
    @typification_map = mappings.select { |m| m.kind == 'typification' }
                                .index_by { |m| m.code.to_s.strip.downcase }
    @advisor_map = mappings.select { |m| m.kind == 'advisor' }
                           .index_by { |m| m.code.to_s.strip.downcase }
  end

  # file_key: la ruta completa en el bucket (puede incluir carpetas y extensión).
  # Devuelve:
  #   {
  #     matched: bool, pattern_id:, raw: { campo => valor },
  #     advisor: JabvoxAudioAdvisor|nil, typification: JabvoxTypification|nil,
  #     phone:, call_id:, date: (Date|nil)
  #   }
  def parse(file_key)
    basename = File.basename(file_key.to_s, File.extname(file_key.to_s))

    @patterns.each do |pattern|
      raw = pattern.parse(basename)
      next unless raw

      return resolve(pattern, raw)
    end

    { matched: false, pattern_id: nil, raw: {}, advisor: nil, typification: nil,
      phone: nil, call_id: nil, date: nil }
  end

  private

  def resolve(pattern, raw)
    advisor = resolve_advisor(raw)
    typification = resolve_typification(raw)

    {
      matched: true,
      pattern_id: pattern.id,
      raw: raw,
      advisor: advisor,
      typification: typification,
      phone: raw['phone'],
      call_id: raw['call_id'],
      date: parse_date(raw['date'], pattern.date_format)
    }
  end

  # El asesor se resuelve SOLO por un mapeo explícito del código/nombre del
  # archivo a un asesor (configurado en la visual). El sistema no infiere: si no
  # hay mapeo, devuelve nil.
  def resolve_advisor(raw)
    mapped = lookup(@advisor_map, raw['advisor_name']) || lookup(@advisor_map, raw['advisor_id'])
    mapped&.advisor
  end

  # La tipificación se resuelve SOLO por un mapeo explícito del código del archivo
  # (p. ej. "AMP") a una tipificación. Sin mapeo configurado, devuelve nil: el
  # código nunca decide la tipificación por su cuenta.
  def resolve_typification(raw)
    mapped = lookup(@typification_map, raw['campaign']) ||
             lookup(@typification_map, raw['typification_id']) ||
             lookup(@typification_map, raw['typification_name'])
    mapped&.typification
  end

  def lookup(map, code)
    return nil if code.blank?

    map[code.to_s.strip.downcase]
  end

  def parse_date(value, fmt)
    return nil if value.blank?

    Date.strptime(value, fmt.presence || '%d-%m-%Y')
  rescue ArgumentError
    # Tolerante: si el formato declarado no casa, intenta parseo flexible y,
    # si tampoco, deja la fecha en nil en vez de romper la ingesta.
    begin
      Date.parse(value)
    rescue StandardError
      nil
    end
  end
end
