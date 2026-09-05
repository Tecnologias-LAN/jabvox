# frozen_string_literal: true

# Agente virtual / Voice Broadcast: campaña saliente que llama a los contactos de una
# JabvoxDialerCampaign y reproduce un audio a quien contesta. Reutiliza la lista de
# contactos del dialer; el motor de marcación y el manejo de eventos AMI son propios
# (Jabvox::VoiceBroadcast::*), sin tocar el dialer predictivo.
# == Schema Information
#
# Table name: jabvox_voice_broadcasts
#
#  id                            :bigint           not null, primary key
#  affiliate_ids_jabvox          :jsonb
#  amd_enabled_jabvox            :boolean          default(TRUE), not null
#  answered_human_count_jabvox   :integer          default(0), not null
#  answered_machine_count_jabvox :integer          default(0), not null
#  audio_deployed_jabvox         :boolean          default(FALSE), not null
#  audio_duration_ms_jabvox      :integer
#  audio_filename_jabvox         :string
#  audio_original_name_jabvox    :string
#  caller_id_jabvox              :string           default(""), not null
#  calling_hours_end_jabvox      :string
#  calling_hours_start_jabvox    :string
#  countries_jabvox              :jsonb
#  cps_jabvox                    :integer          default(1), not null
#  dialed_count_jabvox           :integer          default(0), not null
#  dtmf_enabled_jabvox           :boolean          default(FALSE), not null
#  dtmf_optout_digit_jabvox      :string           default("9")
#  excluded_lead_ids_jabvox      :jsonb            not null
#  failed_count_jabvox           :integer          default(0), not null
#  finished_at_jabvox            :datetime
#  inbox_ids_jabvox              :jsonb
#  lead_filters_jabvox           :jsonb            not null
#  management_state_ids_jabvox   :jsonb
#  max_concurrent_jabvox         :integer          default(5), not null
#  max_retries_jabvox            :integer          default(0), not null
#  name_jabvox                   :string           default(""), not null
#  played_complete_count_jabvox  :integer          default(0), not null
#  retry_interval_jabvox         :integer          default(300), not null
#  source_jabvox                 :string           default("campaign"), not null
#  started_at_jabvox             :datetime
#  status_jabvox                 :string           default("draft"), not null
#  total_recipients_jabvox       :integer          default(0), not null
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  account_id                    :bigint           not null
#  created_by_id                 :bigint
#  jabvox_campaign_id            :bigint
#  jabvox_dialer_campaign_id     :bigint
#
# Indexes
#
#  idx_vb_account         (account_id)
#  idx_vb_account_status  (account_id,status_jabvox)
#  idx_vb_campaign        (jabvox_dialer_campaign_id)
#
class JabvoxVoiceBroadcast < ApplicationRecord
  self.table_name = 'jabvox_voice_broadcasts'

  STATUSES = %w[draft running paused completed stopped].freeze
  # Misma zona horaria que el dialer, para la ventana de marcación.
  SCHEDULE_TZ = 'America/Bogota'
  HOUR_FORMAT = /\A([01]\d|2[0-3]):[0-5]\d\z/

  belongs_to :account
  # Opcional: la campaña de voz puede filtrar sus propios leads (source 'leads') o reusar
  # los contactos de una campaña del dialer (source 'campaign', compat).
  belongs_to :jabvox_dialer_campaign, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :recipients, class_name: 'JabvoxVoiceBroadcastRecipient',
                        inverse_of: :jabvox_voice_broadcast, dependent: :destroy
  has_many :audits, class_name: 'JabvoxVoiceBroadcastAudit',
                    inverse_of: :jabvox_voice_broadcast, dependent: :destroy

  validates :name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validates :max_concurrent_jabvox, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 100 }
  validates :cps_jabvox, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 30 }
  validates :max_retries_jabvox, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :retry_interval_jabvox, numericality: { only_integer: true, greater_than: 0 }
  validates :calling_hours_start_jabvox, format: { with: HOUR_FORMAT }, allow_blank: true
  validates :calling_hours_end_jabvox, format: { with: HOUR_FORMAT }, allow_blank: true

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :ordered, -> { order(created_at: :desc) }
  scope :running, -> { where(status_jabvox: 'running') }

  def running?
    status_jabvox == 'running'
  end

  def audio_ready?
    audio_filename_jabvox.present? && audio_deployed_jabvox
  end

  # ¿Estamos dentro de la ventana horaria configurada? Sin ventana => siempre true.
  def in_schedule?(now = Time.current.in_time_zone(SCHEDULE_TZ))
    return true if calling_hours_start_jabvox.blank? || calling_hours_end_jabvox.blank?

    current = now.strftime('%H:%M')
    current.between?(calling_hours_start_jabvox, calling_hours_end_jabvox)
  end

  # Destinatarios que aún faltan por marcar (pendientes o reintentos elegibles).
  def remaining_recipients_count
    recipients.where(status_jabvox: 'pending').count
  end

  # Cuántos canales del broadcast están activos ahora (para el pacing).
  def in_flight_count
    recipients.where(status_jabvox: 'calling').count
  end

  # Filtros de leads como hash (para el DialerLeadsFilterService), leídos de las columnas.
  def lead_filters_hash(require_phone: true)
    {
      jabvox_campaign_id: jabvox_campaign_id,
      countries: countries_jabvox || [],
      management_state_ids: (management_state_ids_jabvox || []).map(&:to_s),
      affiliate_ids: affiliate_ids_jabvox || [],
      inbox_ids: inbox_ids_jabvox || [],
      excluded_lead_ids: excluded_lead_ids_jabvox || [],
      require_phone: require_phone
    }.merge((lead_filters_jabvox || {}).slice('q', 'email', 'phone', 'document', 'custom'))
  end

  # Scope de leads que esta campaña de voz apunta (source 'leads'). Reusa la misma fuente
  # de verdad que el dialer, así el conteo del formulario = lo que se marca.
  def target_leads_scope
    Jabvox::DialerLeadsFilterService.new(account, lead_filters_hash).scope
  end
end
