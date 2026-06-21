# == Schema Information
#
# Table name: jabvox_whatsapp_templates
#
#  id               :bigint           not null, primary key
#  body_content     :text
#  buttons_json     :jsonb            not null
#  category         :string           default("UTILITY"), not null
#  footer_content   :text
#  header_content   :text
#  header_type      :string
#  language         :string           default("es"), not null
#  meta_json        :jsonb            not null
#  name             :string           not null
#  quality_score    :string
#  rejected_reason  :string
#  status           :string           default("PENDING"), not null
#  variables_json   :jsonb            not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  account_id       :bigint           not null
#  created_by_id    :bigint
#  inbox_id         :bigint           not null
#  meta_template_id :string
#  phone_number_id  :string
#  waba_id          :string
#
# Indexes
#
#  idx_jabvox_wa_templates_account_name_lang            (account_id,name,language)
#  index_jabvox_whatsapp_templates_on_account_id        (account_id)
#  index_jabvox_whatsapp_templates_on_created_by_id     (created_by_id)
#  index_jabvox_whatsapp_templates_on_inbox_id          (inbox_id)
#  index_jabvox_whatsapp_templates_on_meta_template_id  (meta_template_id)
#  index_jabvox_whatsapp_templates_on_status            (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class JabvoxWhatsappTemplate < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_templates'

  belongs_to :account
  belongs_to :inbox
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :versions, class_name: 'JabvoxWhatsappTemplateVersion', dependent: :destroy
  has_many :logs, class_name: 'JabvoxWhatsappTemplateLog', dependent: :destroy

  STATUSES = %w[APPROVED PENDING REJECTED PAUSED DISABLED].freeze
  CATEGORIES = %w[MARKETING UTILITY AUTHENTICATION].freeze
  QUALITY_SCORES = %w[GREEN YELLOW RED UNKNOWN].freeze
  HEADER_TYPES = %w[TEXT IMAGE VIDEO DOCUMENT].freeze

  validates :name, presence: true
  validates :language, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }

  scope :approved, -> { where(status: 'APPROVED') }
  scope :pending, -> { where(status: 'PENDING') }
  scope :rejected, -> { where(status: 'REJECTED') }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_language, ->(lang) { where(language: lang) if lang.present? }
  scope :by_inbox, ->(inbox_id) { where(inbox_id: inbox_id) if inbox_id.present? }
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
      buttons_json: buttons_json, variables_json: variables_json, meta_json: meta_json
    }
  end
end
