# frozen_string_literal: true

require 'rails_helper'

# Request spec (no controller spec): el registro guarda un User con Devise, que necesita
# el middleware Warden del stack completo de requests.
RSpec.describe 'Public::Registration', type: :request do
  before { JabvoxBillingConfig.instance.update!(unpaid_account_cleanup_days: 7) }

  describe 'POST /public/register' do
    # La contraseña debe cumplir la política Devise (mayúscula, minúscula, dígito y especial).
    let(:valid_params) do
      {
        account_name: 'Test Account',
        name: 'John Doe',
        email: 'john@example.com',
        password: 'Password123!',
        password_confirmation: 'Password123!'
      }
    end

    context 'con parámetros válidos' do
      it 'crea una nueva cuenta' do
        expect do
          post '/public/register', params: valid_params
        end.to change(Account, :count).by(1)
      end

      it 'crea un nuevo usuario' do
        expect do
          post '/public/register', params: valid_params
        end.to change(User, :count).by(1)
      end

      it 'la cuenta inicia en estado payment_pending' do
        post '/public/register', params: valid_params
        expect(Account.last.status).to eq('payment_pending')
      end

      it 'el usuario es administrador de la cuenta' do
        post '/public/register', params: valid_params
        account = Account.last
        user = User.last
        expect(account.account_users.find_by(user: user).administrator?).to be true
      end

      it 'encola el correo de bienvenida' do
        expect do
          post '/public/register', params: valid_params
        end.to have_enqueued_mail(Jabvox::Billing::WelcomeMailer, :welcome_email)
      end

      it 'retorna 201 con los datos de la cuenta' do
        post '/public/register', params: valid_params
        expect(response).to have_http_status(:created)
        json = response.parsed_body
        expect(json['email']).to eq('john@example.com')
        expect(json['account_id']).to be_present
        expect(json['user_id']).to be_present
      end
    end

    context 'con email duplicado' do
      before { create(:user, email: 'john@example.com') }

      it 'no crea la cuenta' do
        expect do
          post '/public/register', params: valid_params
        end.not_to change(Account, :count)
      end

      it 'retorna 422 con mensaje de error' do
        post '/public/register', params: valid_params
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to include('registrado')
      end
    end

    context 'con contraseña que no cumple la política' do
      it 'retorna 422 (sin carácter especial)' do
        post '/public/register', params: valid_params.merge(password: 'Password123', password_confirmation: 'Password123')
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'retorna 422 (demasiado corta)' do
        post '/public/register', params: valid_params.merge(password: 'Ab1!', password_confirmation: 'Ab1!')
        expect(response).to have_http_status(:unprocessable_entity)
      end

      # Regresión: una contraseña con acentos/ñ (típica en español) pasaba el chequeo de
      # presencia pero el modelo Devise la rechazaba => 500. Debe ser 422 amigable.
      it 'retorna 422 (con acentos/ñ, no 500)' do
        post '/public/register',
             params: valid_params.merge(password: 'Contraseña1!', password_confirmation: 'Contraseña1!')
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).not_to have_http_status(:internal_server_error)
      end
    end

    context 'con contraseñas que no coinciden' do
      it 'retorna 422' do
        post '/public/register', params: valid_params.merge(password_confirmation: 'Otra123!')
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context 'con parámetros faltantes' do
      it 'retorna error cuando falta email' do
        post '/public/register', params: valid_params.except(:email)
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'retorna error cuando falta name' do
        post '/public/register', params: valid_params.except(:name)
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
