# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::AffiliatesController < Api::V1::Accounts::BaseController
  include JabvoxPermissions

  before_action :check_affiliates_enabled
  # Reading the affiliate list (index) is needed by other modules (e.g. the dialer
  # lead filter). Only WRITE actions require the manage permission; reads stay open
  # to any agent/admin, and the custom-role gate only kicks in for users who
  # actually have a custom role.
  before_action :ensure_module_permission, except: :index
  before_action :set_affiliate, only: %i[update destroy regenerate_token regenerate_code]
  # El afiliado propio no se renombra, no se desactiva y no se borra. Se bloquea
  # aquí ADEMÁS de en el modelo: el endpoint responde 403 con un mensaje claro en
  # vez de un error de validación genérico.
  before_action :reject_owned_affiliate_write, only: %i[update destroy]

  def index
    # El afiliado propio se garantiza al listar: así una cuenta creada antes de
    # esta funcionalidad lo obtiene sin necesidad de un backfill manual.
    JabvoxAffiliate.owned_for!(Current.account)
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

  # Custom-role gate: users without a custom role keep historical access;
  # users with a custom role must be granted the capability (admins always pass).
  def ensure_module_permission
    jabvox_authorize_write!('jabvox_affiliates_manage')
  end

  def set_affiliate
    @affiliate = Current.account.jabvox_affiliates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Not found' }, status: :not_found
  end

  def reject_owned_affiliate_write
    return unless @affiliate&.owned?

    render json: { error: I18n.t('errors.jabvox_affiliate.owned_immutable') }, status: :forbidden
  end

  # owned_jabvox NO es asignable desde la API: el afiliado propio solo lo crea el
  # propio sistema (owned_for!). Permitirlo dejaría crear un segundo "propio" o
  # convertir uno externo en intocable.
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
      # La interfaz usa esto para mostrarlo sin acciones de editar/eliminar.
      owned: affiliate.owned?,
      created_at: affiliate.created_at
    }
  end
end
