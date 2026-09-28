# frozen_string_literal: true

# Comprueba que las claves foráneas salientes apunten a registros de la MISMA cuenta.
#
# El scoping de los controladores protege el recurso que se edita (`Current.account.x.find`),
# pero no lo que ese recurso apunta: `inbox_id`, `sms_provider_id`, `email_template_id` y
# `target_stage_id` viajan en el formulario. Sin esta validación se podía crear una
# automatización propia que enviara mensajes por la bandeja de OTRO cliente, gastara su
# saldo de SMS o renderizara sus plantillas de correo hacia un destinatario elegido.
#
# Se usa así en el modelo:
#
#   include Jabvox::AccountScopedReferences
#   validates_account_scope :inbox, :sms_provider, :email_template
module Jabvox::AccountScopedReferences
  extend ActiveSupport::Concern

  class_methods do
    def validates_account_scope(*names)
      validate do
        names.each do |name|
          record = public_send(name)
          next if record.nil? || record.account_id == account_id

          errors.add(name, :invalid, message: 'no pertenece a esta cuenta')
        end
      end
    end
  end
end
