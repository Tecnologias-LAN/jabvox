# Per-account Bulk WhatsApp config: the n8n webhook URL. Custom-role senders may
# READ it (the send form needs to know the webhook is configured), but only real
# administrators may change where the account's messages are POSTed.
class Api::V1::Accounts::Jabvox::BulkWhatsapp::ConfigController < Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController
  before_action :ensure_admin, only: :show
  before_action :ensure_real_admin, only: :update

  def show
    render json: serialize(config)
  end

  def update
    cfg = config
    if cfg.update(config_params)
      render json: serialize(cfg)
    else
      render json: { errors: cfg.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def ensure_real_admin
    return if Current.account_user&.administrator?

    render json: { error: 'Solo los administradores pueden cambiar la configuración' }, status: :forbidden
  end

  def config
    @config ||= Current.account.jabvox_bulk_whatsapp_config ||
                Current.account.build_jabvox_bulk_whatsapp_config
  end

  def config_params
    params.require(:config).permit(:webhook_url_jabvox)
  end

  def serialize(cfg)
    { webhook_url_jabvox: cfg.webhook_url_jabvox }
  end
end
