# frozen_string_literal: true

# Escucha los eventos del sistema y dispara los flujos de "Automatizaciones
# avanzadas" cuyo trigger `trigger.jabvox_event` coincide. Es el gemelo, para
# flujos, del AutomationRuleListener (Automations nativo) y del WebhookListener:
# usa el MISMO payload que los webhooks de cuenta (`<obj>.webhook_data`), para que
# `{{trigger.*}}` dentro del flujo vea exactamente lo que vería un webhook.
class Jabvox::FlowsEventListener < BaseListener
  def conversation_created(event)
    conversation = extract_conversation_and_account(event)[0]
    dispatch(conversation.account, 'conversation_created', conversation.webhook_data)
  end

  def conversation_updated(event)
    conversation = extract_conversation_and_account(event)[0]
    payload = conversation.webhook_data.merge(changed_attributes: extract_changed_attributes(event))
    dispatch(conversation.account, 'conversation_updated', payload)
  end

  def conversation_status_changed(event)
    conversation = extract_conversation_and_account(event)[0]
    payload = conversation.webhook_data.merge(changed_attributes: extract_changed_attributes(event))
    dispatch(conversation.account, 'conversation_status_changed', payload)
  end

  def message_created(event)
    message = extract_message_and_account(event)[0]
    return unless message.webhook_sendable?

    dispatch(message.account, 'message_created', message.webhook_data)
  end

  def message_updated(event)
    message = extract_message_and_account(event)[0]
    return unless message.webhook_sendable?

    dispatch(message.account, 'message_updated', message.webhook_data)
  end

  def contact_created(event)
    contact, account = extract_contact_and_account(event)
    dispatch(account, 'contact_created', contact.webhook_data)
  end

  def contact_updated(event)
    contact, account = extract_contact_and_account(event)
    dispatch(account, 'contact_updated', contact.webhook_data)
  end

  def webwidget_triggered(event)
    contact_inbox = event.data[:contact_inbox]
    payload = contact_inbox.webhook_data.merge(event_info: event.data[:event_info])
    dispatch(contact_inbox.inbox.account, 'webwidget_triggered', payload)
  end

  private

  def dispatch(account, event_name, payload)
    Jabvox::Flows::EventDispatchService.new(
      account: account, event_name: event_name, payload: payload
    ).call
  end
end
