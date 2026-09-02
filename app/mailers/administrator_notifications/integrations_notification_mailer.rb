class AdministratorNotifications::IntegrationsNotificationMailer < AdministratorNotifications::BaseMailer
  def slack_disconnect
    subject = 'Your Slack integration has expired'
    action_url = settings_url('integrations/slack')
    send_notification(subject, action_url: action_url)
  end

  def dialogflow_disconnect
    subject = 'Your Dialogflow integration was disconnected'
    send_notification(subject)
  end

  def openai_disconnect
    subject = 'Tu integración de Jabvox IA fue desconectada'
    action_url = settings_url('integrations/jabvox_ia')
    send_notification(subject, action_url: action_url)
  end
end
