# frozen_string_literal: true

# Control de sesión del agente aprovisionador sobre el API de RUNS de Hermes: aprobaciones,
# steer, stop y fijar modelo.
#
# Estas acciones son la razón de existir del API de runs: con /chat/completions el agente no
# podía PEDIR APROBACIÓN para ejecutar algo que su escaneo de seguridad marcara, así que se
# quedaba bloqueado sin que el operador llegara a verlo.
module JabvoxProvisioningChatRunControl
  extend ActiveSupport::Concern

  # Responde una aprobación pendiente. `choice` debe venir de approval.choices, que es
  # DINÁMICO (p.ej. sin "always" cuando el hallazgo no admite permiso permanente).
  def approve
    run_id = params[:run_id].to_s
    choice = params[:choice].to_s
    return render_missing('run_id y choice requeridos') if run_id.blank? || choice.blank?

    render_relay(relay.approve(run_id, choice: choice, request_id: params[:request_id]))
  end

  # Inyecta guía a un run EN CURSO (/steer).
  def steer
    run_id = params[:run_id].to_s
    text = params[:text].to_s.strip
    return render_missing('run_id y text requeridos') if run_id.blank? || text.blank?

    render_relay(relay.steer(run_id, text))
  end

  # Interrumpe un run activo.
  def stop_run
    run_id = params[:run_id].to_s
    return render_missing('run_id requerido') if run_id.blank?

    render_relay(relay.stop(run_id))
  end

  # Fija el modelo/proveedor de una sesión de Hermes (/model).
  def set_model
    sid = params[:hermes_session_id].to_s
    model = params[:model].to_s
    return render_missing('hermes_session_id y model requeridos') if sid.blank? || model.blank?

    render_relay(relay.set_session_model(sid, model: model, provider: params[:provider]))
  end

  private

  def relay
    @relay ||= Jabvox::Hermes::ProvisionerChatRelay.new(account: Current.account, user: Current.user)
  end

  def render_missing(message)
    render json: { error: message }, status: :unprocessable_entity
  end

  def render_relay(result)
    if result.success?
      render json: { ok: true, data: result.data }
    else
      render json: { ok: false, error: result.error }, status: :unprocessable_entity
    end
  end
end
