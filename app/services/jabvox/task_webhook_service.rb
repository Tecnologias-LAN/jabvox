require 'uri'

# Delivers a task-move webhook SAFELY: validates the URL is http/https, runs it through the
# SSRF host guard (blocks localhost / private / metadata IPs, resolving every A/AAAA record),
# records an audit row, then POSTs a signed (HMAC-SHA256) payload via the shared
# Webhooks::Trigger path. Never disables the SSRF/security checks.
class Jabvox::TaskWebhookService
  def initialize(automation:, task:)
    @automation = automation
    @task = task
    @account = automation.account
  end

  def perform
    url = @automation.webhook_url_jabvox.to_s.strip
    delivery = build_delivery(url)

    guard = validate_url(url)
    return block!(delivery, guard.reason) unless guard.allowed?

    deliver!(delivery, url)
  rescue StandardError => e
    Rails.logger.error "[TaskWebhook] automation=#{@automation.id} error=#{e.message}"
    delivery&.update(status_jabvox: 'failed', error_jabvox: e.message)
  end

  private

  def build_delivery(url)
    @account.jabvox_task_webhook_deliveries.create!(
      task: @task, automation: @automation, url_jabvox: url,
      status_jabvox: 'pending', payload_jabvox: payload
    )
  end

  # Validates scheme + SSRF. Returns a struct responding to allowed?/reason.
  def validate_url(url)
    uri = begin
      URI.parse(url)
    rescue URI::InvalidURIError
      nil
    end
    return denied('URL inválida') unless uri.is_a?(URI::HTTP) && uri.host.present?

    Jabvox::Analytics::HostGuardService.new(
      host: uri.host, port: uri.port || default_port(uri),
      allowed_ports: Jabvox::Analytics::HostGuardService::ANY_PORT
    ).call
  end

  def default_port(uri)
    uri.scheme == 'https' ? 443 : 80
  end

  def deliver!(delivery, url)
    Webhooks::Trigger.execute(
      url, payload, :account_webhook,
      secret: @automation.webhook_secret_jabvox.presence,
      delivery_id: "jabvox_task_#{delivery.id}"
    )
    delivery.update!(status_jabvox: 'delivered')
  end

  def block!(delivery, reason)
    Rails.logger.warn "[TaskWebhook] blocked url=#{@automation.webhook_url_jabvox} reason=#{reason}"
    delivery.update!(status_jabvox: 'blocked', error_jabvox: reason)
  end

  def payload
    @payload ||= {
      event: 'task.stage_changed',
      task: {
        id: @task.id,
        title: @task.title_jabvox,
        status: @task.status_jabvox,
        priority: @task.priority_jabvox,
        stage: @task.stage&.name_jabvox,
        board: @task.board&.name_jabvox,
        lead_id: @task.contact_id,
        due_at: @task.due_at_jabvox
      },
      account_id: @account.id,
      timestamp: Time.current.to_i
    }
  end

  def denied(reason)
    Struct.new(:allowed, :reason) do
      def allowed? = allowed
    end.new(false, reason)
  end
end
