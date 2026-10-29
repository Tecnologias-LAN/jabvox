class Api::V1::Accounts::Jabvox::Drive::StorageController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_drive'

  # Resumen de cuota de la cuenta activa para el panel del Drive (usado/tope/%).
  def index
    # Consistencia con el resto del módulo: solo agentes/admins de la cuenta.
    authorize JabvoxDriveFile, :index?
    render json: Jabvox::Drive::QuotaService.new(Current.account).summary
  end
end
