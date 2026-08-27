# frozen_string_literal: true

module Jabvox
  module Billing
    # Correos de bienvenida para cuentas nuevas creadas a través del registro público.
    # Envía las credenciales y el link para proceder al pago.
    class WelcomeMailer < ApplicationMailer
      default from: ENV.fetch('MAILER_SENDER_EMAIL', 'noreply@jabvox.com')

      # Correo de bienvenida tras el registro exitoso. Incluye:
      #   - Credenciales de acceso (email)
      #   - Link a la app para iniciar sesión
      #   - Recordatorio de completar el pago para activar el plan
      #
      # Parámetros:
      #   email: correo del usuario
      #   name: nombre del usuario
      #   account_name: nombre de la cuenta creada
      #   login_url: URL de la app para iniciar sesión
      #   cleanup_days: días hasta que la cuenta se elimine sin pago
      def welcome_email(email:, name:, account_name:, login_url:, cleanup_days:)
        @name = name
        @account_name = account_name
        @login_url = login_url
        @email = email
        @cleanup_days = cleanup_days

        mail(
          to: email,
          subject: "¡Bienvenido a Jabvox! Tu cuenta #{account_name} está lista"
        )
      end
    end
  end
end
