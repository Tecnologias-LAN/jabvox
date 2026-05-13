class Api::V1::Accounts::Jabvox::CalendarSettingsController < Api::V1::Accounts::Jabvox::BaseController
  def show
    config = Current.account.jabvox_smtp_config
    render json: serialize(config)
  end

  def update
    config = Current.account.jabvox_smtp_config
    return render json: { error: 'SMTP not configured' }, status: :unprocessable_entity unless config

    config.update!(
      calendar_reminders_enabled: setting_params[:reminders_enabled],
      calendar_reminder_minutes: setting_params[:reminder_minutes] || []
    )
    render json: serialize(config)
  end

  private

  def setting_params
    params.require(:calendar_setting).permit(:reminders_enabled, reminder_minutes: [])
  end

  def serialize(config)
    {
      reminders_enabled: config&.calendar_reminders_enabled || false,
      reminder_minutes: config&.calendar_reminder_minutes || []
    }
  end
end
