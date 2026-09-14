# frozen_string_literal: true

# Pantalla del Super Admin para la API Provisioner: generar el token ÚNICO (se muestra una
# sola vez), configurar la IP allowlist y el checklist de permisos (ver/editar/crear por
# recurso). El super admin NO puede darse permisos a sí mismo aquí — configura los del
# agente Hermes. Nada de esto expone el token guardado (solo el hash vive en BD).
# rubocop:disable Rails/I18nLocaleTexts
class SuperAdmin::ProvisionerApiController < SuperAdmin::ApplicationController
  def show
    @token = JabvoxProvisionerApiToken.current_active
    @summary = @token&.safe_summary
    @resources = JabvoxProvisionerApiToken::RESOURCES
    @read_only = JabvoxProvisionerApiToken::READ_ONLY_RESOURCES
    @actions = JabvoxProvisionerApiToken::ACTIONS
    # El token y el secreto de firma en claro solo existen en flash tras generarlos (una vez).
    @plaintext_once = flash[:provisioner_plaintext]
    @signing_secret_once = flash[:provisioner_signing_secret]
  end

  # Genera/regenera el token único. Revoca el anterior (imposible 2 activos). Muestra el
  # nuevo token UNA sola vez vía flash y redirige.
  def create
    ips = validated_ips!
    return if performed?

    _record, plaintext, signing_secret = JabvoxProvisionerApiToken.generate!(
      created_by_id: current_super_admin&.id,
      allowed_ips: ips,
      # sanitize_permissions se aplica también dentro de generate!, pero se deja explícito
      # aquí para que la regla (nunca delete, solo-lectura no admite edit/create) sea visible
      # en el punto de entrada y no dependa de un detalle del modelo.
      permissions: JabvoxProvisionerApiToken.sanitize_permissions(parse_permissions(params[:permissions])),
      label: params[:label]
    )
    flash[:provisioner_plaintext] = plaintext
    flash[:provisioner_signing_secret] = signing_secret
    redirect_to super_admin_provisioner_api_path, notice: 'Token generado. Copia AHORA el token y el secreto de firma: no se volverán a mostrar.'
  rescue StandardError => e
    Rails.logger.error("[ProvisionerApi] generar: #{e.class}: #{e.message}")
    redirect_to super_admin_provisioner_api_path, alert: 'No se pudo generar el token.'
  end

  # Actualiza IP allowlist y permisos del token activo SIN regenerarlo.
  def update
    token = JabvoxProvisionerApiToken.current_active
    return redirect_to(super_admin_provisioner_api_path, alert: 'No hay token activo') if token.nil?

    ips = validated_ips!
    return if performed?

    token.update!(
      allowed_ips_jabvox: ips,
      permissions_jabvox: JabvoxProvisionerApiToken.sanitize_permissions(parse_permissions(params[:permissions])),
      label_jabvox: params[:label].presence
    )
    redirect_to super_admin_provisioner_api_path, notice: 'Configuración actualizada.'
  rescue StandardError => e
    Rails.logger.error("[ProvisionerApi] actualizar: #{e.class}: #{e.message}")
    redirect_to super_admin_provisioner_api_path, alert: 'No se pudo actualizar la configuración.'
  end

  # Revoca el token activo (y cierra su sesión). No hay borrado: queda como revoked.
  def revoke
    token = JabvoxProvisionerApiToken.current_active
    return redirect_to(super_admin_provisioner_api_path, alert: 'No hay token activo') if token.nil?

    token.revoke!
    # La revocación es un evento de seguridad: queda en la misma auditoría que el resto de
    # la superficie Provisioner, para poder correlacionar "Hermes dejó de responder" con
    # quién cortó el acceso y cuándo.
    JabvoxProvisionerAuditLog.record!(
      token_id: token.id, resource: 'provisioner_token', action: 'edit', outcome: 'ok',
      reason: 'token_revoked_by_super_admin', ip: request.remote_ip,
      params: { 'super_admin_id' => current_super_admin&.id }, status: 200
    )
    redirect_to super_admin_provisioner_api_path, notice: 'Token revocado.'
  end

  private

  def parse_ips(raw)
    raw.to_s.split(/[\s,]+/).map(&:strip).reject(&:blank?)
  end

  # Devuelve la allowlist ya validada. Si alguna entrada no es una IP/CIDR válido (o es una
  # ruta por defecto), redirige con el error y deja `performed?` en true para que quien llama
  # aborte: una allowlist con basura silenciosa deja a Hermes fuera sin explicación, y una
  # ruta por defecto abriría la API a todo internet.
  def validated_ips!
    ips = parse_ips(params[:allowed_ips])
    invalid = ips.reject { |ip| JabvoxProvisionerApiToken.valid_allowlist_entry?(ip) }
    if invalid.any?
      redirect_to(super_admin_provisioner_api_path,
                  alert: "IPs inválidas: #{invalid.join(', ')}. Usa IPs o rangos CIDR (ej. 10.147.0.0/16).")
    end
    ips
  end

  # params[:permissions] llega como { "accounts" => { "view" => "1", "edit" => "1" }, ... }
  # desde los checkboxes → lo transforma a { "accounts" => ["view","edit"] }.
  def parse_permissions(raw)
    return {} unless raw.respond_to?(:each_pair)

    raw.to_unsafe_h.each_with_object({}) do |(res, acts), acc|
      chosen = Array(acts).select { |_k, v| ['1', 'true', true, 'on'].include?(v) }.map(&:first)
      acc[res] = chosen if chosen.any?
    end
  end
end
# rubocop:enable Rails/I18nLocaleTexts
