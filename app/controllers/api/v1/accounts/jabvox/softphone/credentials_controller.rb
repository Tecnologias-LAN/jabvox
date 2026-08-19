# frozen_string_literal: true

# Entrega al navegador las credenciales EFÍMERAS para registrar el softphone WebRTC.
# Gateado por el módulo jabvox_softphone; solo devuelve datos si el usuario tiene una
# extensión ligada. Nunca expone la troncal ni secretos de otras extensiones.
#
# GET /api/v1/accounts/:account_id/jabvox/softphone/credentials
class Api::V1::Accounts::Jabvox::Softphone::CredentialsController < Api::V1::Accounts::Jabvox::BaseController
  jabvox_feature 'jabvox_softphone'

  def show
    result = Jabvox::Softphone::CredentialsService.new(
      account: Current.account, user: Current.user
    ).call
    render json: result, status: :ok
  rescue Jabvox::Softphone::CredentialsError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end
end
