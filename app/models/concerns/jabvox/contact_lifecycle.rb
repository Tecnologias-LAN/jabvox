# frozen_string_literal: true

# Ciclo de vida comercial del contacto: prospecto → interesado → cliente → inactivo.
#
# Sustituye la distinción "es lead / no es lead" que obligaba a tener dos pantallas. Todo
# contacto nace como `prospecto`; cerrar una venta lo pasa a `cliente`, y el resto lo mueve
# el agente o una automatización (por inactividad, por tiempo sin pedido…).
#
# No se toca el `contact_type` de Chatwoot (visitor/lead/customer): ese es del núcleo y lo
# usan otras partes; este es el estado comercial propio de Jabvox.
module Jabvox::ContactLifecycle
  extend ActiveSupport::Concern

  LIFECYCLE_STAGES = %w[prospecto interesado cliente inactivo].freeze
  DEFAULT_STAGE = 'prospecto'

  included do
    validates :lifecycle_stage_jabvox, inclusion: { in: LIFECYCLE_STAGES }, allow_nil: true

    belongs_to :jabvox_campaign, class_name: 'JabvoxCampaign', optional: true
    belongs_to :jabvox_affiliate, class_name: 'JabvoxAffiliate', optional: true
    belongs_to :assignee, class_name: 'User', optional: true

    scope :in_stage, ->(stage) { where(lifecycle_stage_jabvox: stage) if stage.present? }
    scope :sold, -> { where(is_sold_jabvox: true) }
    scope :assigned_to, ->(user_id) { where(assignee_id: user_id) if user_id.present? }
    scope :from_campaign, ->(id) { where(jabvox_campaign_id: id) if id.present? }
    scope :from_affiliate, ->(id) { where(jabvox_affiliate_id: id) if id.present? }

    # Una venta implica que el contacto ya es cliente: se mantienen coherentes para que el
    # filtro por etapa no contradiga a la marca de venta.
    before_save :promote_to_cliente_when_sold
  end

  # Avanza la etapa dejando constancia de quién y cuándo, para poder auditar el embudo.
  def advance_lifecycle!(stage, by: nil)
    raise ArgumentError, "etapa inválida: #{stage}" unless LIFECYCLE_STAGES.include?(stage.to_s)

    update!(lifecycle_stage_jabvox: stage.to_s,
            custom_fields_jabvox: lifecycle_audit(stage, by))
  end

  def lifecycle_stage
    lifecycle_stage_jabvox.presence || DEFAULT_STAGE
  end

  private

  def promote_to_cliente_when_sold
    return unless is_sold_jabvox? && lifecycle_stage_jabvox != 'cliente'

    self.lifecycle_stage_jabvox = 'cliente'
  end

  # El historial vive en custom_fields para no añadir otra tabla: basta saber la etapa
  # anterior y cuándo cambió.
  def lifecycle_audit(stage, actor)
    (custom_fields_jabvox || {}).merge(
      'lifecycle_history' => Array((custom_fields_jabvox || {})['lifecycle_history']).last(9) + [{
        'from' => lifecycle_stage_jabvox, 'to' => stage.to_s,
        'at' => Time.current.iso8601, 'by' => actor&.id
      }]
    )
  end
end
