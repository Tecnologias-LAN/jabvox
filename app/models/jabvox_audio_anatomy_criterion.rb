# Criterio de Anatomía / Cercanía: una dimensión cualitativa de la conversación
# (empatía, escucha activa, naturalidad, personalización…). Se evalúa de forma
# contextual (no por frases exactas) y se reporta como buena práctica (LIKEU) u
# oportunidad de mejora, SIN peso en el score de infaltables.
# == Schema Information
#
# Table name: jabvox_audio_anatomy_criteria
#
#  id                 :bigint           not null, primary key
#  active             :boolean          default(TRUE), not null
#  description        :text             default(""), not null
#  name               :string           not null
#  opportunity_signal :text             default(""), not null
#  position           :integer          default(0), not null
#  positive_signal    :text             default(""), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  created_by_id      :bigint
#
# Indexes
#
#  index_jabvox_audio_anatomy_criteria_on_account_id  (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxAudioAnatomyCriterion < ApplicationRecord
  self.table_name = 'jabvox_audio_anatomy_criteria'

  belongs_to :account
  belongs_to :created_by, class_name: 'User', optional: true

  validates :name, presence: true, length: { maximum: 150 }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :id) }

  # 12 criterios por defecto, tomados del documento de Anatomía LikeU. Son un
  # punto de partida editable: cada cuenta los ajusta a su propia operación.
  DEFAULTS = [
    { name: 'Empatía y conexión', description: 'Comprende la situación, reconoce emoción o necesidad y responde con cercanía.',
      positive_signal: 'Retoma algo que la persona dijo; valida su emoción; trato humano.',
      opportunity_signal: 'Ignorar emoción; responder mecánicamente; sonar frío.' },
    { name: 'Espontaneidad y naturalidad', description: 'La conversación se siente sincera y flexible, no leída palabra por palabra.',
      positive_signal: 'Reacciona a lo que escucha; cambia la formulación según contexto.',
      opportunity_signal: 'Frases rígidas encadenadas; lectura evidente; respuestas prefabricadas.' },
    { name: 'Energía y disposición', description: 'Muestra apertura y energía para relacionarse sin exceso de confianza.',
      positive_signal: 'Entonación viva; interés; iniciativa para sostener la interacción.',
      opportunity_signal: 'Monotonía; apatía; respuestas cortantes.' },
    { name: 'Escucha activa', description: 'Escucha para comprender y usa la información que entrega la persona.',
      positive_signal: 'Pregunta sobre lo escuchado; retoma datos; confirma comprensión.',
      opportunity_signal: 'Pregunta sin escuchar; repite preguntas; interrumpe.' },
    { name: 'Preguntas inteligentes', description: 'Explora necesidades, expectativas y contexto.',
      positive_signal: 'Abiertas para explorar; cerradas para confirmar; conectadas al objetivo.',
      opportunity_signal: 'Preguntas basura; interrogatorio; preguntas con la respuesta incluida.' },
    { name: 'Orientación al cliente y personalización', description: 'Pone a la persona en el centro y adapta la respuesta a su necesidad.',
      positive_signal: 'Respuesta personalizada; usa información del sondeo.',
      opportunity_signal: 'Respuesta genérica; recitar producto.' },
    { name: 'Comunicación cercana y asertiva', description: 'Comunica claro, directo y comprensible, con lenguaje cotidiano pero preciso.',
      positive_signal: 'Términos positivos; explicaciones simples; tuteo cuando corresponde.',
      opportunity_signal: 'Tecnicismos innecesarios; lenguaje burocrático o corporativo.' },
    # NOTA: "Voz LikeU" y "Dicción, vocalización y fluidez" se omiten a propósito:
    # dependen del tono/cadencia/audio y NO son evaluables a partir de la sola
    # transcripción de texto, así que generaban siempre NO_VERIFICABLE.
    { name: 'Criterio, iniciativa y foco', description: 'Toma iniciativa y lleva la conversación hacia una solución.',
      positive_signal: 'Propone; orienta; ofrece alternativas; retoma el objetivo.',
      opportunity_signal: 'Pasividad; pierde el objetivo; no reconduce.' },
    { name: 'Orientación al resultado', description: 'La cercanía está al servicio de un objetivo y la interacción avanza.',
      positive_signal: 'Reconoce señales; conduce al siguiente paso; cierre con acción.',
      opportunity_signal: 'Conversación agradable pero sin avance; cierre débil.' },
    { name: 'Cierre que deja bienestar', description: 'Concreta acuerdos, valida claridad y termina en buenos términos.',
      positive_signal: 'Recuerda acuerdos; valida comprensión; despedida humana.',
      opportunity_signal: 'Cierre abrupto, genérico o que deja incertidumbre.' }
  ].freeze

  # Siembra los criterios por defecto para una cuenta que aún no tiene ninguno.
  def self.seed_defaults!(account, created_by: nil)
    return if exists?(account: account)

    DEFAULTS.each_with_index do |attrs, i|
      create!(attrs.merge(account: account, position: i, created_by: created_by))
    end
  end
end
