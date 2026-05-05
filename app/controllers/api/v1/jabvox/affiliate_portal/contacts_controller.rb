# frozen_string_literal: true

class Api::V1::Jabvox::AffiliatePortal::ContactsController < Api::V1::Jabvox::AffiliatePortal::BaseController
  def create
    @contact = @current_account.contacts.new(contact_params)

    ActiveRecord::Base.transaction do
      @contact.save!
      lead = JabvoxLead.find_or_initialize_by(account: @current_account, contact: @contact)
      lead.jabvox_affiliate = @current_affiliate
      lead.save!

      JabvoxAffiliateImport.create!(
        account: @current_account,
        jabvox_affiliate: @current_affiliate,
        import_type: :manual,
        rows_total: 1,
        rows_ok: 1,
        rows_failed: 0
      )
    end

    render json: {
      id: @contact.id,
      name: @contact.name,
      email: @contact.email,
      phone_number: @contact.phone_number
    }, status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def contact_params
    params.permit(:name, :email, :phone_number,
                  additional_attributes: %i[country city company_name description])
  end
end
