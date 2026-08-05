# Preferencias de notificación de tickets del usuario actual (silenciar in-app y/o
# email). Se guardan en user.ui_settings; cada quien gobierna las suyas.
class Api::V1::Accounts::Jabvox::Tickets::NotificationPreferencesController <
      Api::V1::Accounts::Jabvox::Tickets::BaseController
  def show
    render json: preference.to_h
  end

  def update
    preference.update!(in_app: cast(params[:in_app]), email: cast(params[:email]))
    render json: preference.to_h
  end

  private

  def preference
    @preference ||= Jabvox::Tickets::NotificationPreference.new(Current.user)
  end

  # nil si el param no vino (para no pisar la otra preferencia).
  def cast(value)
    return nil if value.nil?

    ActiveModel::Type::Boolean.new.cast(value)
  end
end
