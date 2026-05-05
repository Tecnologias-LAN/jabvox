# frozen_string_literal: true

# Receives real-time dialer events from the isabell backend and forwards them
# to the relevant agent via ActionCable.
class Api::V1::Accounts::Jabvox::DialerEventsController < Api::V1::Accounts::Jabvox::BaseController
  before_action :require_admin

  def create
    event = params[:event].to_s
    data  = (params[:data] || {}).permit!.to_h.symbolize_keys

    case event
    when 'call_assigned'
      broadcast_to_agent(:call_assigned, enrich_call_assigned(data))
    when 'call_ended'
      mark_contact_ended(data[:dialer_contact_id])
      broadcast_to_agent(:call_ended, data)
    end

    head :ok
  end

  private

  def require_admin
    render json: { error: 'forbidden' }, status: :forbidden unless current_user.administrator?
  end

  def enrich_call_assigned(data) # rubocop:disable Metrics/MethodLength
    contact_rec = Current.account.jabvox_dialer_campaign_contacts.find_by(id: data[:dialer_contact_id])
    return data unless contact_rec

    crm = contact_rec.contact_id ? Current.account.contacts.find_by(id: contact_rec.contact_id) : nil
    lead = contact_rec.contact_id ? Current.account.jabvox_leads
                                                    .includes(:jabvox_affiliate, :jabvox_campaign)
                                                    .find_by(contact_id: contact_rec.contact_id) : nil
    conversation_id = crm ? Current.account.conversations.where(contact_id: crm.id).order(id: :desc).pick(:id) : nil
    last_gestion = fetch_last_management_for_contact(contact_rec.contact_id)

    data.merge(
      contact_name: crm&.name.to_s.presence || contact_rec.name_jabvox,
      contact_phone: contact_rec.phone_jabvox,
      contact_email: crm&.email.to_s,
      contact_country: crm&.country_code.to_s,
      contact_id: contact_rec.contact_id,
      lead_id: lead&.id,
      lead_number: lead&.lead_number,
      affiliate_name: lead&.jabvox_affiliate&.name.to_s,
      campaign_name: lead&.jabvox_campaign&.name_jabvox.to_s,
      conversation_id: conversation_id,
      wrapup_seconds: contact_rec.jabvox_dialer_campaign&.wrapup_time_jabvox.to_i,
      last_management_state: last_gestion&.dig('state_name').to_s,
      last_management_color: last_gestion&.dig('state_color').to_s,
      last_management_note: last_gestion&.dig('note').to_s
    )
  rescue StandardError
    data
  end

  def fetch_last_management_for_contact(contact_id) # rubocop:disable Metrics/MethodLength
    return nil unless contact_id

    msg = Message.joins(:conversation)
                 .where(conversations: { account_id: Current.account.id, contact_id: contact_id })
                 .where(private: true)
                 .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL")
                 .where("(content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''")
                 .order(id: :desc)
                 .first
    return nil unless msg

    {
      'state_name' => msg.content_attributes['jabvox_management_state_name'],
      'state_color' => msg.content_attributes['jabvox_management_state_color'],
      'note' => msg.content
    }
  rescue StandardError
    nil
  end

  def mark_contact_ended(dialer_contact_id)
    return if dialer_contact_id.blank?

    contact = Current.account.jabvox_dialer_campaign_contacts
                     .find_by(id: dialer_contact_id.to_i, status_jabvox: 'calling')
    contact&.update!(status_jabvox: 'no_answer')
  rescue StandardError
    nil
  end

  def broadcast_to_agent(event_name, data)
    user_id = data[:user_id].to_i
    user    = Current.account.users.find_by(id: user_id)
    return unless user

    ActionCable.server.broadcast(user.pubsub_token, {
                                   event: "jabvox.dialer.#{event_name}",
                                   data: data
                                 })
  end
end
