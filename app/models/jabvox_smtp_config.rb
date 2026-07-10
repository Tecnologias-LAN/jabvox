# == Schema Information
#
# Table name: jabvox_smtp_configs
#
#  id                         :bigint           not null, primary key
#  address                    :string
#  authentication             :string           default("login")
#  calendar_reminder_minutes  :text
#  calendar_reminders_enabled :boolean          default(FALSE), not null
#  domain                     :string
#  enable_ssl_tls             :boolean          default(FALSE)
#  enable_starttls_auto       :boolean          default(TRUE)
#  from_email                 :string
#  from_name                  :string
#  password                   :text
#  port                       :integer          default(587)
#  username                   :string
#  verified                   :boolean          default(FALSE)
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#
# Indexes
#
#  index_jabvox_smtp_configs_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxSmtpConfig < ApplicationRecord
  belongs_to :account

  serialize :calendar_reminder_minutes, coder: JSON

  validates :from_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :port, numericality: { only_integer: true, greater_than: 0, less_than: 65_536 }, allow_nil: true
  validates :authentication, inclusion: { in: %w[plain login cram_md5] }

  encrypts :password if Jabvox.encryption_configured?

  def delivery_settings
    {
      address: address,
      port: port || 587,
      domain: domain.presence || address,
      user_name: username.presence,
      password: password.presence,
      # Only send AUTH when we actually have credentials; an anonymous relay
      # otherwise rejects the login handshake.
      authentication: (authentication || 'login' if username.present?),
      enable_starttls_auto: enable_starttls_auto,
      tls: enable_ssl_tls,
      openssl_verify_mode: 'none',
      # Cap the SMTP round-trip so a wrong host/port or a firewall doesn't hang
      # the web request until the browser gives up.
      open_timeout: 10,
      read_timeout: 15
    }.compact
  end
end
