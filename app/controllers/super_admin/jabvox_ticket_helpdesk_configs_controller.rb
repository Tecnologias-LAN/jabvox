# rubocop:disable Rails/I18nLocaleTexts
class SuperAdmin::JabvoxTicketHelpdeskConfigsController < SuperAdmin::ApplicationController
  before_action :set_config, only: [:edit, :update, :destroy]

  def index
    @configs = JabvoxTicketHelpdeskConfig.includes(:account).order(created_at: :desc)
  end

  def new
    @config = JabvoxTicketHelpdeskConfig.new(active_jabvox: true, auto_assign_mode_jabvox: :manual)
  end

  def edit; end

  def create
    @config = JabvoxTicketHelpdeskConfig.new(config_params)
    if @config.save
      deactivate_others(@config)
      redirect_to super_admin_jabvox_ticket_helpdesk_configs_path, notice: 'Helpdesk config created successfully.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @config.update(config_params)
      deactivate_others(@config)
      redirect_to super_admin_jabvox_ticket_helpdesk_configs_path, notice: 'Helpdesk config updated successfully.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @config.destroy!
    redirect_to super_admin_jabvox_ticket_helpdesk_configs_path, notice: 'Helpdesk config deleted.'
  end

  private

  def set_config
    @config = JabvoxTicketHelpdeskConfig.find(params[:id])
  end

  # Singleton lógico: solo una config activa a la vez. Al activar una, desactiva el resto.
  def deactivate_others(config)
    return unless config.active_jabvox?

    JabvoxTicketHelpdeskConfig.where(active_jabvox: true)
                              .where.not(id: config.id)
                              .update_all(active_jabvox: false, updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
  end

  def config_params
    params.require(:jabvox_ticket_helpdesk_config)
          .permit(:account_id, :auto_assign_mode_jabvox, :resolver_visibility_jabvox, :active_jabvox)
          .merge(business_hours_jabvox: normalized_business_hours)
  end

  # Normaliza el bloque de horario laboral del formulario a un hash tipado.
  def normalized_business_hours
    bh = params[:business_hours]
    return {} if bh.blank?

    {
      'enabled' => ActiveModel::Type::Boolean.new.cast(bh[:enabled]),
      'days' => Array(bh[:days]).map(&:to_i).uniq.sort,
      'start_minute' => bh[:start_minute].to_i,
      'end_minute' => bh[:end_minute].to_i,
      'time_zone' => bh[:time_zone].to_s.presence || 'UTC'
    }
  end
end
# rubocop:enable Rails/I18nLocaleTexts
