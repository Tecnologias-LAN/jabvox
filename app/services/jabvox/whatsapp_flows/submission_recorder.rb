# Hooked into the WhatsApp incoming-message webhook pipeline (architecture doc section
# 2.6/5.5) right after Whatsapp::IncomingMessageServiceHelpers#add_flow_response_attributes
# has stashed the raw answers into content_attributes['whatsapp_flow_response']. Does NOT
# replace that raw storage — it's additional, structured persistence on top of it.
#
# Resolution path for "which JabvoxWhatsappFlow is this a reply to": the flow_token Meta
# echoes back in the incoming nfm_reply was minted by
# Whatsapp::PopulateTemplateParametersService#build_flow_button_parameter at send time and
# stored on the OUTGOING message's additional_attributes.template_params.processed_params.buttons
# — the exact same field/path Jabvox::BulkWhatsappFlowReply#flow_token_from_additional_attributes
# already reads for the bulk-campaign report. We reuse that same reading, not reimplement it.
class Jabvox::WhatsappFlows::SubmissionRecorder
  include Jabvox::BulkWhatsappFlowReply

  def initialize(account)
    @account = account
  end

  # message: the incoming Message record (already saved, nfm_reply) whose
  # content_attributes['whatsapp_flow_response'] was just populated.
  # Degrades gracefully on any miss (no flow_token, no matching outgoing message, no
  # matching JabvoxWhatsappFlow, no matching flow version) — never raises into the
  # webhook, never blocks the existing raw content_attributes behavior.
  def record(message)
    answers = message.content_attributes&.dig('whatsapp_flow_response')
    return nil if answers.blank?

    flow_token = answers['flow_token']
    return nil if flow_token.blank?

    return existing_for(flow_token) if submission_already_recorded?(flow_token)

    flow = resolve_flow(message, flow_token)
    return nil if flow.blank?

    create_submission(flow, message, flow_token, answers)
  rescue StandardError => e
    Rails.logger.error "[WA Flows] SubmissionRecorder failed for message=#{message&.id}: #{e.message}"
    nil
  end

  private

  def submission_already_recorded?(flow_token)
    @account.jabvox_whatsapp_flow_submissions.exists?(flow_token: flow_token)
  end

  def existing_for(flow_token)
    @account.jabvox_whatsapp_flow_submissions.find_by(flow_token: flow_token)
  end

  # Finds the outgoing message that minted this flow_token (same field this account's
  # bulk report already scans), then reads which JabvoxWhatsappFlow it was sent for.
  # The outgoing send doesn't carry a jabvox_whatsapp_flow_id itself (only Meta's raw
  # flow_id in the button), so we match on Channel::Whatsapp -> JabvoxWhatsappFlow via
  # the resolved meta_flow_id, scoped to this account (never a bare .find).
  def resolve_flow(message, flow_token)
    outgoing = @account.messages
                       .where(conversation_id: message.conversation_id, message_type: :outgoing)
                       .where("additional_attributes -> 'template_params' -> 'processed_params' -> 'buttons' IS NOT NULL")
                       .order(created_at: :desc)
                       .find { |m| flow_token_from_additional_attributes(m.additional_attributes) == flow_token }
    return nil if outgoing.blank?

    meta_flow_id = outgoing.additional_attributes.dig('template_params', 'processed_params', 'buttons')
                           &.find { |b| b['type'] == 'flow' }
                           &.dig('flow_id')
    return nil if meta_flow_id.blank?

    @account.jabvox_whatsapp_flows.find_by(meta_flow_id: meta_flow_id)
  end

  def create_submission(flow, message, flow_token, answers)
    ActiveRecord::Base.transaction do
      submission = @account.jabvox_whatsapp_flow_submissions.create!(
        jabvox_whatsapp_flow: flow,
        jabvox_whatsapp_flow_version: flow.current_version_number,
        contact_id: message.conversation&.contact_id || message.sender_id,
        conversation_id: message.conversation_id,
        message_id: message.id,
        flow_token: flow_token,
        status: 'completed',
        raw_response_json: answers,
        completed_at: message.created_at || Time.current
      )
      create_answers(submission, flow, answers)
      submission
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "[WA Flows] SubmissionRecorder could not persist submission: #{e.message}"
    nil
  end

  def create_answers(submission, flow, answers)
    component_index = index_components(flow.screens_json)

    answers.except('flow_token').each do |field_key, value|
      meta = component_index[field_key]
      submission.answers.create!(
        screen_id: meta&.fetch(:screen_id, nil) || 'unknown',
        component_id: meta&.fetch(:component_id, nil) || field_key,
        component_name: field_key,
        component_type: meta&.fetch(:type, nil) || 'unknown',
        value_text: humanize_value(value)
      )
    end
  end

  # { component "name" => { screen_id:, component_id:, type: } } across every screen of
  # the flow's current definition, used to resolve each response_json key back to the
  # screen/component it came from (for aggregating answers per-question in reports).
  def index_components(screens_json)
    Array(screens_json).each_with_object({}) do |screen, out|
      screen_id = screen['id'] || screen[:id]
      Array(screen['components'] || screen[:components]).each do |component|
        props = component['props'] || component[:props] || {}
        name = props['name'] || props[:name]
        next if name.blank?

        out[name] = {
          screen_id: screen_id,
          component_id: component['id'] || component[:id],
          type: component['type'] || component[:type]
        }
      end
    end
  end

  def humanize_value(value)
    Array(value).join(', ')
  end
end
