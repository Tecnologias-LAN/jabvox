require 'rails_helper'

# Seguridad: el token de sesión ahora TAMBIÉN se entrega en una cookie HttpOnly (además de
# los headers que el JS sigue usando normalmente vía axios). A diferencia de la cookie
# cw_d_session_info (js-cookie, legible por cualquier script), esta cookie NUNCA es visible
# para JavaScript — cierra el vector de robo de token vía document.cookie en caso de XSS.
# Confirma que: (1) el login deja la cookie con httponly real, (2) esa cookie sola (sin
# ningún header de auth) basta para autenticar un request — necesario para los flujos que no
# pueden mandar headers manualmente (streaming SSE, beacons al cerrar pestaña).
RSpec.describe 'DeviseTokenAuth HttpOnly cookie', type: :request do
  let(:user) { create(:user, password: 'Test@123456') }

  it 'sets an httponly auth cookie on successful login' do
    post '/auth/sign_in', params: { email: user.email, password: 'Test@123456' }

    expect(response).to have_http_status(:success)
    # response.headers['Set-Cookie'] es un array (una entrada por cookie); hay que
    # buscar la línea exacta de auth_cookie, no tratar el array entero como string.
    auth_cookie_line = Array(response.headers['Set-Cookie']).find { |c| c.start_with?('auth_cookie=') }
    expect(auth_cookie_line).to be_present
    expect(auth_cookie_line).to include('httponly')
  end

  it 'authenticates a request using ONLY the cookie, with no auth headers at all' do
    post '/auth/sign_in', params: { email: user.email, password: 'Test@123456' }
    auth_cookie = response.cookies['auth_cookie']
    expect(auth_cookie).to be_present

    get '/api/v1/profile', headers: { 'Cookie' => "auth_cookie=#{auth_cookie}" }

    expect(response).to have_http_status(:success)
    expect(response.parsed_body['email']).to eq(user.email)
  end

  it 'rejects a request with no cookie and no headers' do
    get '/api/v1/profile'

    expect(response).to have_http_status(:unauthorized)
  end

  it 'clears the cookie on logout' do
    post '/auth/sign_in', params: { email: user.email, password: 'Test@123456' }
    access_token = response.headers['access-token']
    client = response.headers['client']

    delete '/auth/sign_out', headers: { 'access-token' => access_token, :client => client, :uid => user.email }

    set_cookie_header = response.headers['Set-Cookie'].to_s
    expect(set_cookie_header).to include('auth_cookie=;').or include('auth_cookie=""')
  end
end
