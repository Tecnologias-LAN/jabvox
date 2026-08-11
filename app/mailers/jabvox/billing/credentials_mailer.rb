# frozen_string_literal: true

# Envía al comprador el correo de bienvenida con el link SEGURO para establecer su
# contraseña cuando el aprovisionamiento creó una cuenta nueva.
#
# Seguridad: el link lleva un token Devise de un solo uso y con expiración; NO se envía
# contraseña ni ningún dato sensible en el correo ni en la URL.
class Jabvox::Billing::CredentialsMailer < ApplicationMailer
  layout false # vista autocontenida; no usa el layout liquid de los mailers de conversación

  def set_password(email:, account_name:, set_password_url:)
    @account_name = account_name
    @set_password_url = set_password_url
    mail(to: email, subject: I18n.t('jabvox.billing.credentials_mailer.set_password.subject'))
  end
end
