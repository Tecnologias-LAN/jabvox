# frozen_string_literal: true

require 'rails_helper'

# Horario laboral por agente.
#
# Antes bastaba el permiso del módulo: cualquier agente reescribía en bloque el turno de un
# compañero (la acción borra y recrea) o el horario de empresa que sirve de respaldo a toda
# la cuenta.
RSpec.describe 'Jabvox agent availabilities', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }

  let(:agent) { agent_with_calendar_permission }
  let(:colleague) { agent_with_calendar_permission }

  before { account.update!(jabvox_calendar_enabled_jabvox: true) }

  def agent_with_calendar_permission
    user = create(:user, account: account, role: :agent)
    role = account.custom_roles.create!(name: "Cal #{SecureRandom.hex(3)}",
                                        permissions: ['jabvox_calendar_manage'])
    account.account_users.find_by(user: user).update!(custom_role: role)
    user
  end

  def url(id) = "/api/v1/accounts/#{account.id}/jabvox/agent_availabilities/#{id}"

  def payload
    { availabilities: [{ day_of_week: 1, start_minute: 540, end_minute: 1080,
                         slot_minutes: 30, active: true }] }
  end

  describe 'quién puede editar cada horario' do
    it 'un agente edita el suyo' do
      patch url(agent.id), params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'no puede editar el de un compañero' do
      patch url(colleague.id), params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(account.jabvox_agent_availabilities.where(user_id: colleague.id)).to be_empty
    end

    # El horario de empresa es el respaldo de toda la cuenta.
    it 'no puede editar el de la empresa' do
      patch url('company'), params: payload, headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it 'el administrador edita el de cualquiera' do
      patch url(agent.id), params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end

    it 'el administrador edita el de la empresa' do
      patch url('company'), params: payload, headers: admin.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
    end
  end

  describe 'jornada partida' do
    it 'admite dos tramos el mismo día' do
      patch url(agent.id),
            params: { availabilities: [
              { day_of_week: 1, start_minute: 360, end_minute: 720, slot_minutes: 30, active: true },
              { day_of_week: 1, start_minute: 840, end_minute: 1080, slot_minutes: 30, active: true }
            ] },
            headers: agent.create_new_auth_token, as: :json

      expect(response).to have_http_status(:success)
      expect(account.jabvox_agent_availabilities.where(user_id: agent.id).count).to eq(2)
    end
  end
end
