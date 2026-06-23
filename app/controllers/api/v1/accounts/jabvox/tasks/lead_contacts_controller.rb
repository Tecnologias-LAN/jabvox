# Info-only contact people for a lead (right-hand panel). Pure reference data — never
# creates real contacts/leads, never used to place calls.
class Api::V1::Accounts::Jabvox::Tasks::LeadContactsController < Api::V1::Accounts::Jabvox::Tasks::BaseController
  before_action :set_contact, only: %i[update destroy]

  def index
    contacts = scoped
    contacts = contacts.where(jabvox_lead_id: params[:lead_id]) if params[:lead_id].present?
    render json: contacts.ordered.map { |c| serialize(c) }
  end

  def create
    contact = scoped.new(contact_params)
    contact.account = Current.account
    contact.created_by = current_user
    if contact.save
      render json: serialize(contact), status: :created
    else
      render json: { errors: contact.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @contact.update(contact_params)
      render json: serialize(@contact)
    else
      render json: { errors: @contact.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.destroy!
    head :no_content
  end

  private

  def scoped
    Current.account.jabvox_task_lead_contacts
  end

  def set_contact
    @contact = scoped.find(params[:id])
  end

  def contact_params
    params.require(:lead_contact).permit(
      :jabvox_lead_id, :name_jabvox, :role_jabvox, :email_jabvox, :phone_jabvox,
      :description_jabvox, :position_jabvox
    )
  end

  def serialize(contact)
    {
      id: contact.id, jabvox_lead_id: contact.jabvox_lead_id, name_jabvox: contact.name_jabvox,
      role_jabvox: contact.role_jabvox, email_jabvox: contact.email_jabvox,
      phone_jabvox: contact.phone_jabvox, description_jabvox: contact.description_jabvox,
      position_jabvox: contact.position_jabvox
    }
  end
end
