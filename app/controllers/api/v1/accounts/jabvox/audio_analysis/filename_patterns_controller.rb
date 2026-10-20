# CRUD de patrones de nombre de archivo + un endpoint de prueba para que el
# usuario vea en vivo cómo se parsea un nombre antes de guardar el patrón.
class Api::V1::Accounts::Jabvox::AudioAnalysis::FilenamePatternsController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_access
  before_action :ensure_can_manage, only: [:create, :update, :destroy]
  before_action :set_pattern, only: [:update, :destroy]

  def index
    render json: {
      patterns: Current.account.jabvox_audio_filename_patterns.ordered.map { |p| serialize(p) },
      known_fields: JabvoxAudioFilenamePattern::KNOWN_FIELDS
    }
  end

  def create
    pattern = Current.account.jabvox_audio_filename_patterns.create!(
      pattern_params.merge(created_by: current_user)
    )
    render json: serialize(pattern), status: :created
  end

  def update
    @pattern.update!(pattern_params)
    render json: serialize(@pattern)
  end

  def destroy
    @pattern.destroy!
    head :no_content
  end

  # POST /filename_patterns/test — prueba un patrón contra un nombre de ejemplo
  # y devuelve los campos extraídos y a qué asesor/tipificación se vincularían.
  # No guarda nada.
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def test
    pattern = JabvoxAudioFilenamePattern.new(
      account: Current.account, name: 'test',
      pattern: params[:pattern].to_s, date_format: params[:date_format].presence || '%d-%m-%Y'
    )
    unless pattern.valid?
      render json: { error: pattern.errors.full_messages.join(', ') }, status: :unprocessable_entity
      return
    end

    # Acota el ejemplo: es solo para previsualizar el parseo, no un archivo real.
    sample = params[:sample].to_s.first(JabvoxAudioFilenamePattern::MAX_BASENAME)
    raw = pattern.parse(File.basename(sample, File.extname(sample)))
    if raw.nil?
      render json: { matched: false }
      return
    end

    # Resuelve asesor y tipificación SOLO por los mapeos configurados (sin asumir),
    # igual que lo hará la ingesta real.
    advisor = JabvoxAudioCodeMapping.advisor_for(Current.account, raw['advisor_name']) ||
              JabvoxAudioCodeMapping.advisor_for(Current.account, raw['advisor_id'])
    typification = JabvoxAudioCodeMapping.typification_for(Current.account, raw['campaign']) ||
                   JabvoxAudioCodeMapping.typification_for(Current.account, raw['typification_id']) ||
                   JabvoxAudioCodeMapping.typification_for(Current.account, raw['typification_name'])
    render json: {
      matched: true, fields: raw,
      advisor: advisor && { id: advisor.id, name: advisor.name },
      typification: typification && { id: typification.id, name: typification.name }
    }
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  private

  def set_pattern
    @pattern = Current.account.jabvox_audio_filename_patterns.find(params[:id])
  end

  def pattern_params
    params.require(:filename_pattern).permit(:name, :pattern, :date_format, :active, :position)
  end

  def serialize(pattern)
    {
      id: pattern.id, name: pattern.name, pattern: pattern.pattern,
      date_format: pattern.date_format, active: pattern.active,
      position: pattern.position, fields: pattern.fields
    }
  end
end
