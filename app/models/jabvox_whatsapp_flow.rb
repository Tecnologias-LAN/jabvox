# == Schema Information
#
# Table name: jabvox_whatsapp_flows
#
#  id                     :bigint           not null, primary key
#  category               :string           not null
#  description            :text
#  meta_json              :jsonb            not null
#  meta_status            :string
#  name                   :string           not null
#  published_at           :datetime
#  screens_json           :jsonb            not null
#  status                 :string           default("draft"), not null
#  validation_errors_json :jsonb            not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  account_id             :bigint           not null
#  created_by_id          :bigint
#  inbox_id               :bigint           not null
#  meta_flow_id           :string
#  waba_id                :string           not null
#
# Indexes
#
#  idx_jabvox_wa_flows_account_meta_flow_id      (account_id,meta_flow_id)
#  idx_jabvox_wa_flows_account_name              (account_id,name)
#  index_jabvox_whatsapp_flows_on_account_id     (account_id)
#  index_jabvox_whatsapp_flows_on_created_by_id  (created_by_id)
#  index_jabvox_whatsapp_flows_on_inbox_id       (inbox_id)
#  index_jabvox_whatsapp_flows_on_status         (status)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#
class JabvoxWhatsappFlow < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_flows'

  belongs_to :account
  belongs_to :inbox
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :versions, class_name: 'JabvoxWhatsappFlowVersion', dependent: :destroy
  has_many :submissions, class_name: 'JabvoxWhatsappFlowSubmission', dependent: :destroy

  # Local Jabvox lifecycle (see architecture doc section 6) — distinct from meta_status,
  # which mirrors what Meta reports and is only ever set by MetaClient#fetch_status.
  STATUSES = %w[draft validating ready published sync_failed].freeze
  # Meta's own Flow status (Graph API), synced verbatim, never inferred locally.
  META_STATUSES = %w[DRAFT PUBLISHED DEPRECATED BLOCKED THROTTLED].freeze
  CATEGORIES = %w[SIGN_UP SIGN_IN APPOINTMENT_BOOKING LEAD_GENERATION CONTACT_US CUSTOMER_SUPPORT SURVEY OTHER].freeze

  validates :name, presence: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :status, inclusion: { in: STATUSES }
  validates :meta_status, inclusion: { in: META_STATUSES }, allow_nil: true
  validates :waba_id, presence: true

  scope :draft, -> { where(status: 'draft') }
  scope :published, -> { where(status: 'published') }
  scope :by_category, ->(cat) { where(category: cat) if cat.present? }
  scope :by_inbox, ->(inbox_id) { where(inbox_id: inbox_id) if inbox_id.present? }
  scope :search_text, lambda { |q|
    where('name ILIKE ? OR description ILIKE ?', "%#{q}%", "%#{q}%") if q.present?
  }

  # A Flow PUBLISHED on Meta is immutable there (Graph API rejects further JSON
  # updates) — the builder must block edits to screens_json once this is true.
  def published_on_meta?
    meta_status == 'PUBLISHED'
  end

  def current_version_number
    versions.maximum(:version) || 1
  end

  def snapshot_payload
    { screens_json: screens_json }
  end
end
