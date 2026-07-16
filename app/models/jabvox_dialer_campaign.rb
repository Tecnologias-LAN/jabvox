# == Schema Information
#
# Table name: jabvox_dialer_campaigns
#
#  id                          :bigint           not null, primary key
#  affiliate_ids_jabvox        :jsonb
#  agent_ids_jabvox            :jsonb
#  answered_count_jabvox       :integer          default(0), not null
#  caller_id_jabvox            :string           default("")
#  calling_hours_end_jabvox    :string
#  calling_hours_start_jabvox  :string
#  countries_jabvox            :jsonb
#  description_jabvox          :text
#  dial_field_jabvox           :string
#  dial_mode_jabvox            :string           default("last_state"), not null
#  dial_prefix_jabvox          :string
#  dialed_count_jabvox         :integer          default(0), not null
#  excluded_lead_ids_jabvox    :jsonb            not null
#  failed_count_jabvox         :integer          default(0), not null
#  inbox_ids_jabvox            :jsonb
#  lead_filters_jabvox         :jsonb            not null
#  leads_count_jabvox          :integer          default(0), not null
#  lines_per_agent_jabvox      :integer          default(1)
#  management_state_ids_jabvox :jsonb
#  max_concurrent_jabvox       :integer          default(1), not null
#  max_retries_jabvox          :integer          default(0), not null
#  name_jabvox                 :string           default(""), not null
#  retry_count_jabvox          :integer          default(0), not null
#  retry_interval_jabvox       :integer          default(60), not null
#  retry_statuses_jabvox       :jsonb            not null
#  schedule_end_date_jabvox    :date
#  schedule_start_date_jabvox  :date
#  status_jabvox               :string           default("draft"), not null
#  total_contacts_jabvox       :integer          default(0), not null
#  wait_in_queue_jabvox        :boolean          default(TRUE), not null
#  wrapup_time_jabvox          :integer          default(30)
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  jabvox_campaign_id          :bigint
#
# Indexes
#
#  index_jabvox_dialer_campaigns_on_account_id          (account_id)
#  index_jabvox_dialer_campaigns_on_jabvox_campaign_id  (jabvox_campaign_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (jabvox_campaign_id => jabvox_campaigns.id) ON DELETE => nullify
#
class JabvoxDialerCampaign < ApplicationRecord
  self.table_name = 'jabvox_dialer_campaigns'

  STATUSES = %w[draft active paused completed].freeze
  CALL_STATUSES = %w[initiated answered busy no_answer failed].freeze
  DIAL_MODES = %w[last_state one_by_one].freeze

  belongs_to :account
  belongs_to :jabvox_campaign, optional: true
  has_many :jabvox_dialer_campaign_contacts,
           inverse_of: :jabvox_dialer_campaign,
           dependent: :destroy
  has_many :jabvox_dialer_call_logs,
           inverse_of: :jabvox_dialer_campaign,
           dependent: :destroy

  # Same timezone the dialer reports use; the management window is evaluated here.
  SCHEDULE_TZ = 'America/Bogota'.freeze
  HOUR_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  validates :name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :dial_mode_jabvox, inclusion: { in: DIAL_MODES }
  validates :max_concurrent_jabvox, numericality: { only_integer: true, greater_than: 0 }
  validates :retry_count_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :retry_interval_jabvox, numericality: { only_integer: true, greater_than: 0 }
  validates :calling_hours_start_jabvox, format: { with: HOUR_FORMAT }, allow_blank: true
  validates :calling_hours_end_jabvox, format: { with: HOUR_FORMAT }, allow_blank: true
  validate :schedule_dates_ordered
  validate :calling_hours_ordered

  scope :ordered, -> { order(created_at: :desc) }
  scope :active, -> { where(status_jabvox: 'active') }

  # True when the campaign may be managed right now: today falls inside the
  # date window (when set) AND the local time falls inside the calling hours
  # (when set). Campaigns without a window are always manageable.
  def in_schedule?(now = Time.current.in_time_zone(SCHEDULE_TZ))
    today = now.to_date
    return false if schedule_start_date_jabvox.present? && today < schedule_start_date_jabvox
    return false if schedule_end_date_jabvox.present? && today > schedule_end_date_jabvox

    hhmm = now.strftime('%H:%M')
    return false if calling_hours_start_jabvox.present? && hhmm < calling_hours_start_jabvox
    return false if calling_hours_end_jabvox.present? && hhmm > calling_hours_end_jabvox

    true
  end

  private

  def schedule_dates_ordered
    return if schedule_start_date_jabvox.blank? || schedule_end_date_jabvox.blank?
    return if schedule_end_date_jabvox >= schedule_start_date_jabvox

    errors.add(:schedule_end_date_jabvox, 'must be on or after the start date')
  end

  def calling_hours_ordered
    return if calling_hours_start_jabvox.blank? || calling_hours_end_jabvox.blank?
    return unless calling_hours_start_jabvox.match?(HOUR_FORMAT) && calling_hours_end_jabvox.match?(HOUR_FORMAT)
    return if calling_hours_end_jabvox > calling_hours_start_jabvox

    errors.add(:calling_hours_end_jabvox, 'must be after the start hour')
  end
end
