class Api::V1::Accounts::Jabvox::EmailTemplatesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :set_template, only: [:show, :update, :destroy, :test_send, :send_to_contact]

  def index
    @templates = Current.account.jabvox_email_templates.order(created_at: :desc)
  end

  def show; end

  def create
    unless JabvoxEmailTemplate.within_limit?(Current.account)
      limit = JabvoxEmailTemplate.limit_for(Current.account)
      return render json: { error: "Template limit reached (#{limit})" }, status: :unprocessable_entity
    end

    @template = Current.account.jabvox_email_templates.create!(template_params)
    render :show, status: :created
  end

  def update
    @template.update!(template_params)
    render :show
  end

  def destroy
    @template.destroy!
    head :no_content
  end

  def send_to_contact
    config = Current.account.jabvox_smtp_config
    return render json: { error: 'SMTP not configured' }, status: :unprocessable_entity if config&.address.blank?

    contact = Current.account.contacts.find(params[:contact_id])
    return render json: { error: 'Contact has no email' }, status: :unprocessable_entity if contact.email.blank?

    deliver_template(@template, config, contact)
    render json: { success: true }
  rescue StandardError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def test_send
    config = Current.account.jabvox_smtp_config
    return render json: { error: 'SMTP not configured' }, status: :unprocessable_entity if config&.address.blank?

    to = params[:to].to_s.strip
    return render json: { error: 'Recipient email is required' }, status: :unprocessable_entity if to.blank?

    template = @template

    Mail.new do
      from    "#{config.from_name} <#{config.from_email}>"
      to      to
      subject template.subject
      html_part do
        content_type 'text/html; charset=UTF-8'
        body template.body.to_s
      end
    end.tap { |m| m.delivery_method(:smtp, config.delivery_settings) }.deliver!

    config.update!(verified: true)
    render json: { success: true }
  rescue StandardError => e
    config&.update(verified: false)
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def set_template
    @template = Current.account.jabvox_email_templates.find(params[:id])
  end

  def template_params
    params.require(:email_template).permit(:name, :subject, :body, :active)
  end

  def deliver_template(template, config, contact)
    body    = interpolate(template.body.to_s, contact)
    subject = interpolate(template.subject.to_s, contact)
    to_addr = contact.email
    from_str = "#{config.from_name} <#{config.from_email}>"

    mail = Mail.new do
      from    from_str
      to      to_addr
      subject subject
      html_part do
        content_type 'text/html; charset=UTF-8'
        body body
      end
    end
    mail.delivery_method(:smtp, config.delivery_settings)
    mail.deliver!
  end

  def interpolate(text, contact)
    text
      .gsub('{{contact_name}}', contact.name.to_s)
      .gsub('{{contact_email}}', contact.email.to_s)
      .gsub('{{contact_phone}}', contact.phone_number.to_s)
  end
end
