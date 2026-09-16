# == Schema Information
#
# Table name: jabvox_whatsapp_templates
#
#  id                      :bigint           not null, primary key
#  auth_config_json        :jsonb            not null
#  body_content            :text
#  buttons_json            :jsonb            not null
#  cards_json              :jsonb            not null
#  category                :string           default("UTILITY"), not null
#  footer_content          :text
#  header_content          :text
#  header_type             :string
#  language                :string           default("es"), not null
#  limited_time_offer      :boolean          default(FALSE), not null
#  location_header         :boolean          default(FALSE), not null
#  meta_json               :jsonb            not null
#  name                    :string           not null
#  quality_score           :string
#  rejected_reason         :string
#  status                  :string           default("PENDING"), not null
#  template_kind           :string           default("standard"), not null
#  variables_json          :jsonb            not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  account_id              :bigint           not null
#  created_by_id           :bigint
#  inbox_id                :bigint           not null
#  jabvox_whatsapp_flow_id :bigint
#  meta_template_id        :string
#  phone_number_id         :string
#  waba_id                 :string
#
# Indexes
#
#  idx_jabvox_wa_templates_account_name_lang                   (account_id,name,language)
#  index_jabvox_whatsapp_templates_on_account_id               (account_id)
#  index_jabvox_whatsapp_templates_on_created_by_id            (created_by_id)
#  index_jabvox_whatsapp_templates_on_inbox_id                 (inbox_id)
#  index_jabvox_whatsapp_templates_on_jabvox_whatsapp_flow_id  (jabvox_whatsapp_flow_id)
#  index_jabvox_whatsapp_templates_on_meta_template_id         (meta_template_id)
#  index_jabvox_whatsapp_templates_on_status                   (status)
#  index_jabvox_whatsapp_templates_on_template_kind            (template_kind)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#  fk_rails_...  (jabvox_whatsapp_flow_id => jabvox_whatsapp_flows.id)
#
class JabvoxWhatsappTemplate < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_templates'

  belongs_to :account
  belongs_to :inbox
  belongs_to :created_by, class_name: 'User', optional: true
  # Flow que abre el botón de la plantilla, cuando se creó desde el mismo wizard.
  belongs_to :jabvox_whatsapp_flow, class_name: 'JabvoxWhatsappFlow', optional: true
  has_many :versions, class_name: 'JabvoxWhatsappTemplateVersion', dependent: :destroy
  has_many :logs, class_name: 'JabvoxWhatsappTemplateLog', dependent: :destroy

  STATUSES = %w[APPROVED PENDING REJECTED PAUSED DISABLED].freeze
  CATEGORIES = %w[MARKETING UTILITY AUTHENTICATION].freeze
  QUALITY_SCORES = %w[GREEN YELLOW RED UNKNOWN].freeze
  HEADER_TYPES = %w[TEXT IMAGE VIDEO DOCUMENT LOCATION].freeze
  # 'standard': texto/imagen/video/documento/location libre, con o sin botones normales.
  # 'authentication': modo OTP (body/footer generados por Meta, un solo botón OTP).
  # 'carousel': cards_json maneja el componente CAROUSEL adicional.
  # 'flow' es una plantilla estándar cuyo botón abre un WhatsApp Flow. El Flow
  # vive en su propio registro (JabvoxWhatsappFlow) porque Meta los trata como
  # objetos separados, pero el wizard deja crearlo en el mismo paso.
  TEMPLATE_KINDS = %w[standard authentication carousel flow].freeze

  validates :name, presence: true
  validates :language, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :template_kind, inclusion: { in: TEMPLATE_KINDS }
  # NOTA: se evita deliberadamente cualquier validate de presencia condicional sobre
  # body_content/cards_json aquí. upsert_from_meta (sync) usa create!/update! sobre
  # templates AUTHENTICATION/CAROUSEL ya existentes en Meta que Jabvox no creó, y
  # cuya forma exacta (p.ej. sin body_content libre) no debe romper el sync. La
  # validación real de "¿esta plantilla está completa para crear/actualizar en
  # Meta?" vive en Jabvox::WhatsappTemplatesManager (server-side, sobre params
  # antes de llamar a Meta) y en useTemplateValidation.js (UX en vivo).

  scope :approved, -> { where(status: 'APPROVED') }
  scope :pending, -> { where(status: 'PENDING') }
  scope :rejected, -> { where(status: 'REJECTED') }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_language, ->(lang) { where(language: lang) if lang.present? }
  scope :by_inbox, ->(inbox_id) { where(inbox_id: inbox_id) if inbox_id.present? }
  scope :by_kind, ->(kind) { where(template_kind: kind) if kind.present? }
  scope :search_text, lambda { |q|
    where('name ILIKE ? OR body_content ILIKE ?', "%#{q}%", "%#{q}%") if q.present?
  }

  def current_version_number
    versions.maximum(:version) || 1
  end

  def snapshot_payload
    {
      name: name, language: language, category: category, status: status,
      header_type: header_type, header_content: header_content,
      body_content: body_content, footer_content: footer_content,
      buttons_json: buttons_json, variables_json: variables_json, meta_json: meta_json,
      template_kind: template_kind, cards_json: cards_json, auth_config_json: auth_config_json,
      location_header: location_header, limited_time_offer: limited_time_offer
    }
  end
end
