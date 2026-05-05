class Api::V1::Accounts::Jabvox::DialerCallLogsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :check_authorization

  def index
    logs = Current.account.jabvox_dialer_call_logs.ordered.limit(200)
    render json: logs.map { |log| log_json(log) }
  end

  def create
    contact = Current.account.jabvox_dialer_campaign_contacts.find(params[:contact_id])
    log = build_call_log(contact)
    update_contact_after_call(contact, log)
    update_campaign_counters(contact.jabvox_dialer_campaign, log)
    render json: log_json(log), status: :created
  end

  private

  def check_authorization
    authorize :jabvox_dialer_call_log
  end

  def build_call_log(contact)
    Current.account.jabvox_dialer_call_logs.create!(
      jabvox_dialer_campaign_id: contact.jabvox_dialer_campaign_id,
      jabvox_dialer_campaign_contact_id: contact.id,
      phone_jabvox: contact.phone_jabvox,
      status_jabvox: params[:status_jabvox] || 'initiated',
      duration_jabvox: params[:duration_jabvox].to_i,
      started_at_jabvox: params[:started_at_jabvox],
      ended_at_jabvox: params[:ended_at_jabvox],
      agent_id_jabvox: current_user.id,
      notes_jabvox: params[:notes_jabvox]
    )
  end

  def update_contact_after_call(contact, log)
    contact.update!(
      status_jabvox: log.status_jabvox == 'answered' ? 'completed' : log.status_jabvox,
      attempts_jabvox: contact.attempts_jabvox + 1,
      last_attempt_at_jabvox: Time.current
    )
  end

  def update_campaign_counters(campaign, log)
    # rubocop:disable Rails/SkipsModelValidations
    JabvoxDialerCampaign.update_counters(campaign.id, dialed_count_jabvox: 1)
    JabvoxDialerCampaign.update_counters(campaign.id, answered_count_jabvox: 1) if log.status_jabvox == 'answered'
    JabvoxDialerCampaign.update_counters(campaign.id, failed_count_jabvox: 1) if %w[failed busy no_answer].include?(log.status_jabvox)
    # rubocop:enable Rails/SkipsModelValidations
  end

  def log_json(log)
    {
      id: log.id,
      jabvox_dialer_campaign_id: log.jabvox_dialer_campaign_id,
      jabvox_dialer_campaign_contact_id: log.jabvox_dialer_campaign_contact_id,
      phone_jabvox: log.phone_jabvox,
      status_jabvox: log.status_jabvox,
      duration_jabvox: log.duration_jabvox,
      started_at_jabvox: log.started_at_jabvox,
      ended_at_jabvox: log.ended_at_jabvox,
      notes_jabvox: log.notes_jabvox,
      agent_id_jabvox: log.agent_id_jabvox,
      created_at: log.created_at
    }
  end
end
