class JabvoxFormsController < ApplicationController
  layout false

  before_action :set_form
  before_action :set_security_headers

  def show; end

  def submit
    data = build_submission_data
    errors = validate_fields(data)

    if errors.any?
      render json: { errors: errors }, status: :unprocessable_entity
      return
    end

    submission = JabvoxFormSubmission.create!(
      jabvox_form: @form,
      account: @form.account,
      data_jabvox: data,
      ip_address_jabvox: request.remote_ip
    )

    process_submit_actions(submission)
    render json: { success: true }
  rescue ActiveRecord::RecordInvalid => e
    render json: { errors: [e.message] }, status: :unprocessable_entity
  end

  private

  def set_security_headers
    response.headers['X-Frame-Options']          = 'DENY'
    response.headers['X-Content-Type-Options']   = 'nosniff'
    response.headers['Referrer-Policy']          = 'strict-origin-when-cross-origin'
    response.headers['Permissions-Policy']       = 'camera=(), microphone=(), geolocation=()'
    response.headers['Content-Security-Policy']  = [
      "default-src 'none'",
      "script-src 'unsafe-inline'",
      "style-src 'unsafe-inline'",
      "img-src * data: blob:",
      "connect-src 'self'",
      "form-action 'self'",
      "frame-ancestors 'none'",
      "base-uri 'none'"
    ].join('; ')
  end

  def set_form
    @form = JabvoxForm.active.find_by!(
      account_id: params[:account_id],
      slug_jabvox: params[:slug]
    )
  rescue ActiveRecord::RecordNotFound
    render file: Rails.public_path.join('404.html'), status: :not_found, layout: false
  end

  def build_submission_data
    fields = @form.fields_jabvox || []
    raw_data = begin
      params[:form_data].to_unsafe_h
    rescue StandardError
      {}
    end
    data = {}
    fields.each do |field|
      id = field['id'].to_s
      raw = raw_data[id].to_s.strip
      data[id] = ActionController::Base.helpers.sanitize(raw, tags: [], attributes: [])
    end
    data
  end

  EMAIL_RE  = /\A[^\s@]+@[^\s@]+\.[^\s@]+\z/
  PHONE_RE  = %r{\A[\+\d\s\-()/.]{7,25}\z}
  CEDULA_RE = /\A\d{5,15}\z/

  def validate_fields(data)
    errors = []
    (@form.fields_jabvox || []).each do |field|
      value = data[field['id'].to_s].to_s
      validate_single_field(field, value, errors)
    end
    errors
  end

  def validate_single_field(field, value, errors)
    label = field['label'].to_s
    errors << "#{label} es requerido" if field['required'] && value.blank?
    check_field_format(field['type'], label, value, errors) if value.present?
  end

  def check_field_format(type, label, value, errors)
    case type
    when 'email'  then errors << "#{label}: formato de correo inválido" unless value.match?(EMAIL_RE)
    when 'phone'  then errors << "#{label}: formato de teléfono inválido" unless value.match?(PHONE_RE)
    when 'cedula' then errors << "#{label}: solo se permiten números (5-15 dígitos)" unless value.match?(CEDULA_RE)
    when 'pais'   then nil
    else          errors << "#{label}: máximo 40 caracteres" if value.length > 40
    end
  end

  def process_submit_actions(submission)
    contact_data = extract_contact_fields(submission.data_jabvox, @form.fields_jabvox || [])
    create_contact_and_lead(contact_data)

    actions = @form.submit_actions_jabvox || {}
    trigger_email_action(submission, actions['email'], contact_data[:email])
    trigger_webhook_action(submission, actions['webhook'])
  rescue StandardError
    nil
  end

  def trigger_email_action(submission, email_action, to_email)
    return unless email_action&.dig('enabled') && email_action['template_id'].present? && to_email.present?

    deliver_email_notification(submission, email_action, to_email)
  end

  def trigger_webhook_action(submission, webhook_config)
    return unless webhook_config&.dig('enabled') && webhook_config['url'].present?

    deliver_webhook(submission, webhook_config)
  end

  def create_contact_and_lead(contact_data)
    return unless contact_data[:email].present? || contact_data[:phone].present?

    account  = @form.account
    contact  = find_or_create_contact(account, contact_data)
    campaign = account.jabvox_campaigns.find_or_create_by!(name_jabvox: @form.name_jabvox)
    JabvoxLead.create!(account: account, contact: contact, jabvox_campaign: campaign) unless
      JabvoxLead.exists?(account_id: account.id, contact_id: contact.id)
  rescue StandardError
    nil
  end

  def extract_contact_fields(data, fields)
    result = { email: nil, phone: nil, name: nil }
    fields.each { |field| apply_to_contact_data(result, field, data[field['id'].to_s].to_s.strip) }
    result
  end

  NAME_LABEL_RE = /\bnombre\b|\bname\b/

  # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
  def apply_to_contact_data(result, field, val)
    return if val.blank?

    result[:email] ||= val if field['type'] == 'email'
    result[:phone] ||= val if field['type'] == 'phone'
    result[:name]  ||= val if field['type'] == 'text' && field['label'].to_s.downcase.match?(NAME_LABEL_RE)
  end
  # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

  def find_or_create_contact(account, data)
    email = data[:email]
    phone = data[:phone]
    name  = data[:name]
    if email.present?
      account.contacts.from_email(email) ||
        account.contacts.create!(name: name.presence || email.split('@').first,
                                 email: email, phone_number: phone.presence)
    else
      account.contacts.find_by(phone_number: phone) ||
        account.contacts.create!(name: name.presence || phone, phone_number: phone)
    end
  end

  def deliver_email_notification(submission, email_action, to_email)
    smtp_config = @form.account.jabvox_smtp_config
    return if smtp_config&.address.blank?

    subject_text, body_text = resolve_email_template(submission, email_action['template_id'].to_s)
    full_body = build_email_body(submission, body_text)
    send_mail(smtp_config, to_email, subject_text, full_body)
  rescue StandardError
    nil
  end

  def resolve_email_template(submission, template_id)
    if template_id.present?
      tpl = @form.account.jabvox_email_templates.find_by(id: template_id)
      return [tpl.subject, tpl.body.to_s] if tpl
    end
    ["Nueva respuesta: #{submission.jabvox_form.name_jabvox}", '']
  end

  def build_email_body(submission, body_text)
    form_data_block = submission.data_jabvox.map do |field_id, value|
      field = (@form.fields_jabvox || []).find { |f| f['id'].to_s == field_id }
      "#{field ? field['label'] : field_id}: #{value}"
    end.join("\n")
    body_text.present? ? "#{body_text}\n\n---\n#{form_data_block}" : form_data_block
  end

  def send_mail(smtp_config, to_email, subject_text, full_body)
    mail = Mail.new do
      from    "#{smtp_config.from_name} <#{smtp_config.from_email}>"
      to      to_email
      subject subject_text
      body    full_body
    end
    mail.delivery_method(:smtp, smtp_config.delivery_settings)
    mail.deliver!
  end

  # rubocop:disable Metrics/MethodLength, Metrics/AbcSize
  def deliver_webhook(submission, webhook_config)
    url    = webhook_config['url']
    secret = webhook_config['secret'].to_s
    payload = {
      form_id: @form.id,
      form_name: @form.name_jabvox,
      submitted_at: submission.created_at.iso8601,
      data: submission.data_jabvox
    }.to_json

    headers = { 'Content-Type' => 'application/json' }
    headers['X-Jabvox-Signature'] = OpenSSL::HMAC.hexdigest('SHA256', secret, payload) if secret.present?

    uri  = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl     = uri.scheme == 'https'
    http.open_timeout = 5
    http.read_timeout = 10
    req      = Net::HTTP::Post.new(uri.request_uri, headers)
    req.body = payload
    http.request(req)
  rescue StandardError
    nil
  end
  # rubocop:enable Metrics/MethodLength, Metrics/AbcSize
end
