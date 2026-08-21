class Api::V1::Widget::DirectUploadsController < ActiveStorage::DirectUploadsController
  include WebsiteTokenHelper
  before_action :set_web_widget
  before_action :set_contact
  before_action :ensure_storage_quota

  def create
    return if @contact.nil? || @current_account.nil?

    super
  end

  private

  def ensure_storage_quota
    byte_size = params.dig(:blob, :byte_size).to_i
    return if byte_size <= 0
    return unless @current_account&.storage_over_quota?(byte_size)

    render json: { error: 'La cuenta no tiene almacenamiento disponible para este archivo' },
           status: :payment_required
  end
end
