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
    _record, plaintext, signing_secret = JabvoxProvisionerApiToken.generate!(
      created_by_id: current_super_admin&.id,
      allowed_ips: parse_ips(params[:allowed_ips]),
      permissions: parse_permissions(params[:permissions]),
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

    token.update!(
      allowed_ips_jabvox: parse_ips(params[:allowed_ips]),
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
    JabvoxProvisionerApiToken.current_active&.revoke!
    redirect_to super_admin_provisioner_api_path, notice: 'Token revocado.'
  end

  private

  def parse_ips(raw)
    raw.to_s.split(/[\s,]+/).map(&:strip).reject(&:blank?)
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
