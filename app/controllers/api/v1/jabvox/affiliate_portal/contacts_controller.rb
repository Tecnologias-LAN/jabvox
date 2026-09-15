# frozen_string_literal: true

# Alta manual de un lead desde el portal de afiliados.
#
# Aplica las mismas reglas de identidad que la carga masiva: el prefijo sale del
# país elegido, la comparación con lo existente es exacta y, si el lead ya
# existe, se rechaza — el afiliado nunca actualiza un lead ajeno.
class Api::V1::Jabvox::AffiliatePortal::ContactsController < Api::V1::Jabvox::AffiliatePortal::BaseController
  def create
    return render_error('country_required', :unprocessable_entity) unless
      Jabvox::LeadIdentityService.valid_country?(country_iso)

    result = importer.import_one(
      name: contact_params[:name], phone_raw: contact_params[:phone_number],
      email_raw: contact_params[:email], city: contact_params.dig(:additional_attributes, :city)
    )

    case result.outcome
    when :ok then render json: serialize(result.contact), status: :created
    when :duplicated then render_error('duplicate_lead', :conflict)
    else render_error('invalid_contact', :unprocessable_entity)
    end
  end

  private

  def country_iso
    @country_iso ||= (params[:country].presence || contact_params.dig(:additional_attributes, :country)).to_s.strip.upcase
  end

  # Mismas reglas de identidad que la carga masiva: el afiliado nunca actualiza
  # un lead que ya existe.
  def importer
    @importer ||= Jabvox::AffiliateLeadImporter.new(
      account: @current_account, affiliate: @current_affiliate,
      country_iso: country_iso, campaign_name: params[:campaign]
    )
  end

  def render_error(code, status)
    render json: { error: code }, status: status
  end

  def serialize(contact)
    { id: contact.id, name: contact.name, email: contact.email, phone_number: contact.phone_number }
  end

  def contact_params
    @contact_params ||= params.permit(:name, :email, :phone_number,
                                      additional_attributes: %i[country city company_name description])
  end
end
