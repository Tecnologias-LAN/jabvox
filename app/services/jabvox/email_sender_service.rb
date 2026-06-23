# Single entry point for sending an email through a Jabvox SMTP config.
# Mirrors exactly what each call site did before (Mail.new + delivery_settings
# + deliver!) and additionally records a JabvoxEmailSendLog row so the Email
# analytics report can count sends.
#
# The logging is strictly best-effort: if recording the log raises, the email
# has already been delivered and the error is swallowed (logged to Rails.logger)
# so delivery is never blocked by analytics bookkeeping.
#
#   Jabvox::EmailSenderService.new(
#     account: account, config: account.jabvox_smtp_config,
#     to: 'x@y.com', subject: 'Hi', html_body: '<p>...</p>',
#     source: 'manual', user: current_user
#   ).deliver!
class Jabvox::EmailSenderService
  # rubocop:disable Metrics/ParameterLists -- these are the fields of one email; a hash would hurt readability
  def initialize(account:, config:, to:, subject:, html_body:, source: 'system', user: nil)
    @account = account
    @config = config
    @to = to
    @subject = subject.to_s
    @html_body = html_body.to_s
    @source = source
    @user = user
  end
  # rubocop:enable Metrics/ParameterLists

  # Sends the email and logs the outcome. Returns the Mail object. Raises only
  # if the actual delivery fails (same behavior as the original call sites),
  # and records a 'failed' log row before re-raising.
  def deliver!
    build_mail.tap(&:deliver!)
    record_log(status: 'sent')
  rescue StandardError => e
    record_log(status: 'failed', error: e.message)
    raise
  end

  private

  def build_mail
    config = @config
    from_str = "#{config.from_name} <#{config.from_email}>"
    to_addr = @to
    subject_str = @subject
    body_str = @html_body

    mail = Mail.new do
      from from_str
      to to_addr
      subject subject_str
      html_part do
        content_type 'text/html; charset=UTF-8'
        body body_str
      end
    end
    mail.delivery_method(:smtp, config.delivery_settings)
    mail
  end

  def record_log(status:, error: nil)
    JabvoxEmailSendLog.create!(
      account_id: @account.id,
      user_id: @user&.id,
      to_email: @to.to_s,
      subject: @subject.first(255),
      status: status,
      source: @source,
      error_message: error,
      sent_at: status == 'sent' ? Time.current : nil
    )
  rescue StandardError => e
    # Never let analytics logging break (or mask) email delivery.
    Rails.logger.error "[Jabvox::EmailSenderService] log failed: #{e.message}"
  end
end
