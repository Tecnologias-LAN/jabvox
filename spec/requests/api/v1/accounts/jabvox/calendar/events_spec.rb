# frozen_string_literal: true

require 'rails_helper'

# El calendario es de equipo: ver que un compañero está ocupado es necesario para cuadrar
# horarios. Ver con quién se reúne y por qué, no. Antes el listado devolvía descripción,
# notas y el contacto de TODAS las citas de la cuenta, así que la agenda de un comercial
# revelaba su cartera entera.
RSpec.describe 'Jabvox calendar events', type: :request do
  let(:account) { create(:account) }
  # Escribir en el calendario exige `jabvox_calendar_manage` (comportamiento previo). Se
  # les concede para que los ejemplos midan la propiedad del evento, no el permiso del
  # módulo, que ya está cubierto en otra parte.
  let(:owner) { agent_with_calendar_permission }
  let(:colleague) { agent_with_calendar_permission }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:contact) { create(:contact, account: account, name: 'Cliente VIP') }

  let!(:event) do
    account.jabvox_calendar_events.create!(
      user: owner, title: 'Cita con Cliente VIP',
      description: 'Negociar descuento', note: 'No mencionar al competidor',
      contact: contact, start_at: 2.hours.from_now, end_at: 3.hours.from_now
    )
  end

  before { account.update!(jabvox_calendar_enabled_jabvox: true) }

  def agent_with_calendar_permission
    user = create(:user, account: account, role: :agent)
    role = account.custom_roles.create!(name: "Cal #{SecureRandom.hex(3)}",
                                        permissions: ['jabvox_calendar_manage'])
    account.account_users.find_by(user: user).update!(custom_role: role)
    user
  end

  def index_url
    "/api/v1/accounts/#{account.id}/jabvox/calendar_events" \
      "?from=#{1.hour.ago.iso8601}&to=#{1.day.from_now.iso8601}"
  end

  def event_url(record = event)
    "/api/v1/accounts/#{account.id}/jabvox/calendar_events/#{record.id}"
  end

  def listed_by(user)
    get index_url, headers: user.create_new_auth_token, as: :json
    response.parsed_body.find { |e| e['id'] == event.id }
  end

  describe 'lo que ve un compañero' do
    it 've la franja ocupada' do
      row = listed_by(colleague)

      expect(row['start_at']).to be_present
      expect(row['end_at']).to be_present
    end

    it 'no ve el título real, que suele llevar el nombre del cliente' do
      expect(listed_by(colleague)['title']).not_to include('Cliente VIP')
    end

    it 'no ve la descripción ni la nota interna' do
      row = listed_by(colleague)

      expect(row['description']).to be_nil
      expect(row['note']).to be_nil
    end

    it 'no ve el contacto de la cita' do
      row = listed_by(colleague)

      expect(row['contact_id']).to be_nil
      expect(row['contact_name']).to be_nil
      expect(row['contact_email']).to be_nil
    end

    it 'no ve la lista de invitados' do
      expect(listed_by(colleague)['participants']).to eq([])
    end

    it 'sabe que no puede gestionarla' do
      expect(listed_by(colleague)['can_manage']).to be(false)
    end
  end

  describe 'lo que ve quien la organiza' do
    it 've el detalle completo' do
      row = listed_by(owner)

      expect(row['title']).to eq('Cita con Cliente VIP')
      expect(row['description']).to eq('Negociar descuento')
      expect(row['contact_name']).to eq('Cliente VIP')
      expect(row['can_manage']).to be(true)
    end
  end

  describe 'lo que ve un administrador' do
    it 've el detalle de cualquier cita de su cuenta' do
      expect(listed_by(admin)['description']).to eq('Negociar descuento')
    end
  end

  describe 'quién puede modificarla' do
    it 'un compañero no puede editarla' do
      patch event_url, params: { title: 'Secuestrada' },
                       headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(event.reload.title).to eq('Cita con Cliente VIP')
    end

    it 'un compañero no puede borrarla' do
      delete event_url, headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(JabvoxCalendarEvent.where(id: event.id)).to exist
    end

    it 'quien la organiza sí puede editarla' do
      patch event_url, params: { title: 'Reprogramada' },
                       headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(event.reload.title).to eq('Reprogramada')
    end

    it 'el administrador puede editar cualquiera' do
      patch event_url, params: { title: 'Ajustada' },
                       headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    # Un invitado participa en la cita, así que puede tocarla.
    it 'un invitado puede gestionarla' do
      event.jabvox_calendar_event_participants.create!(user: colleague)

      patch event_url, params: { title: 'Movida por invitado' },
                       headers: colleague.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  # El gate de la acción valida el evento pedido, pero borrar una serie opera sobre N:
  # estar invitado a una cita permitía borrar las demás, que ni siquiera se podían ver.
  describe 'borrar una serie recurrente' do
    let(:group) { SecureRandom.uuid }

    def serie_event(owner_user, title)
      account.jabvox_calendar_events.create!(
        user: owner_user, title: title, recurrence_group_id: group,
        start_at: 2.hours.from_now, end_at: 3.hours.from_now
      )
    end

    it 'solo borra las citas que el usuario puede gestionar' do
      mia = serie_event(colleague, 'Mía')
      ajena = serie_event(owner, 'Ajena')

      delete "#{event_url(mia)}?scope=group",
             headers: colleague.create_new_auth_token, as: :json

      expect(JabvoxCalendarEvent.where(id: mia.id)).to be_empty
      expect(JabvoxCalendarEvent.where(id: ajena.id)).to exist
    end

    it 'el administrador sí borra la serie completa' do
      una = serie_event(owner, 'Una')
      otra = serie_event(colleague, 'Otra')

      delete "#{event_url(una)}?scope=group",
             headers: admin.create_new_auth_token, as: :json

      expect(JabvoxCalendarEvent.where(id: [una.id, otra.id])).to be_empty
    end
  end

  describe 'aislamiento entre cuentas' do
    let(:other_account) { create(:account) }

    it 'no deja enlazar un contacto de otra cuenta' do
      ajeno = create(:contact, account: other_account, name: 'Confidencial')

      post "/api/v1/accounts/#{account.id}/jabvox/calendar_events",
           params: { title: 'X', contact_id: ajeno.id,
                     start_at: 2.hours.from_now.iso8601, end_at: 3.hours.from_now.iso8601 },
           headers: owner.create_new_auth_token, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).not_to include('Confidencial')
    end

    it 'descarta un invitado de otra cuenta en vez de añadirlo' do
      ajeno = create(:user, account: other_account)

      patch event_url, params: { participants: [{ user_id: ajeno.id }] },
                       headers: owner.create_new_auth_token, as: :json

      expect(event.reload.jabvox_calendar_event_participants.pluck(:user_id)).not_to include(ajeno.id)
    end
  end
end
