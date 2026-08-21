class Api::V1::Accounts::Conversations::DirectUploadsController < ActiveStorage::DirectUploadsController
  include DeviseTokenAuth::Concerns::SetUserByToken
  include RequestExceptionHandler
  include AccessTokenAuthHelper
  include EnsureCurrentAccountHelper

  skip_before_action :verify_authenticity_token, if: :authenticate_by_access_token?

  around_action :handle_with_exception
  before_action :authenticate_access_token!, if: :authenticate_by_access_token?
  before_action :validate_bot_access_token!, if: :authenticate_by_access_token?
  before_action :authenticate_user!, unless: :authenticate_by_access_token?
  before_action :current_account
  before_action :validate_token_api_access, if: :authenticate_by_access_token?
  before_action :conversation
  before_action :ensure_storage_quota

  def create
    return if @conversation.nil? || @current_account.nil?

    super
  end

  private

  def authenticate_by_access_token?
    request.headers[:api_access_token].present? || request.headers[:HTTP_API_ACCESS_TOKEN].present?
  end

  def validate_token_api_access
    return if Current.account.api_and_webhooks_enabled?

    render json: { error: 'API access is not enabled for this account' }, status: :forbidden
  end

  def conversation
    @conversation ||= Current.account.conversations.find_by(display_id: params[:conversation_id])
  end

  def ensure_storage_quota
    byte_size = params.dig(:blob, :byte_size).to_i
    return if byte_size <= 0
    return unless Current.account.storage_over_quota?(byte_size)

    render json: { error: 'La cuenta no tiene almacenamiento disponible para este archivo' },
           status: :payment_required
  end
end
