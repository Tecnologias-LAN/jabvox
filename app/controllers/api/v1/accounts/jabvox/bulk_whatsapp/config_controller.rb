# Per-account Bulk WhatsApp config: the n8n webhook URL. Admin-only.
class Api::V1::Accounts::Jabvox::BulkWhatsapp::ConfigController < Api::V1::Accounts::Jabvox::BulkWhatsapp::BaseController
  before_action :ensure_admin

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
