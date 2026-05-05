# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::AffiliatesController < Api::V1::Accounts::BaseController
  before_action :check_affiliates_enabled
  before_action :set_affiliate, only: %i[update destroy regenerate_token regenerate_code]

  def index
    @affiliates = Current.account.jabvox_affiliates.ordered
    render json: @affiliates.map { |a| serialize_affiliate(a) }
  end

  def create
    @affiliate = Current.account.jabvox_affiliates.new(affiliate_params)
    @affiliate.save!
    render json: serialize_affiliate(@affiliate), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @affiliate.update!(affiliate_params)
    render json: serialize_affiliate(@affiliate)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @affiliate.destroy!
    head :ok
  end

  def regenerate_token
    @affiliate.regenerate_auth_token!
    render json: serialize_affiliate(@affiliate)
  end

  def regenerate_code
    @affiliate.regenerate_account_code!
    render json: serialize_affiliate(@affiliate)
  end

  def portal_login_url
    base = "#{request.protocol}#{request.host_with_port}"
    render json: { url: "#{base}/#{Current.account.id}/affiliate-portal" }
  end

  private

  def check_affiliates_enabled
    render json: { error: 'Affiliates module not enabled' }, status: :forbidden unless Current.account.jabvox_affiliates_enabled_jabvox?
  end

  def set_affiliate
    @affiliate = Current.account.jabvox_affiliates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def affiliate_params
    params.permit(:name, :active)
  end

  def portal_base_url
    "#{request.protocol}#{request.host_with_port}/#{Current.account.id}/affiliate-portal"
  end

  def serialize_affiliate(affiliate)
    {
      id: affiliate.id,
      name: affiliate.name,
      account_code: affiliate.account_code,
      auth_token: affiliate.auth_token,
      portal_slug: affiliate.portal_slug,
      portal_url: "#{portal_base_url}/login/#{affiliate.portal_slug}",
      active: affiliate.active,
      created_at: affiliate.created_at
    }
  end
end
