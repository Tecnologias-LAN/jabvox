# Credencial ENTRANTE: la API key propia con la que Jabvox opera una cuenta contra
# Automations. Separada del selector de usuario (credencial SALIENTE), que es otra cosa.
module SuperAdmin::AccountAutomationsApiKey
  extend ActiveSupport::Concern

  # rubocop:disable Rails/I18nLocaleTexts

  # Campo vacío = "conservar la actual", no "borrarla": la key no se re-renderiza en el
  # formulario, así que tratar el blanco como borrado dejaría la cuenta sin credencial.
  def update_api_key
    if params[:remove_api_key].present?
      @config.assign_api_key(nil)
      persist_api_key!('Credencial de la cuenta eliminada. Esta cuenta volverá a usar la Provision Key maestra.')
      return
    end

    raw = params[:api_key].to_s.strip
    if raw.blank?
      redirect_to super_admin_account_account_automations_path(@account),
                  notice: 'No se hicieron cambios: se conserva la credencial actual de la cuenta.'
      return
    end

    @config.assign_api_key(raw)
    persist_api_key!('Credencial de la cuenta guardada. Usa "Probar conexión de esta cuenta" para verificarla.')
  end

  # Prueba la credencial de esta cuenta contra la plataforma remota. El resultado se
  # guarda en la fila de ESTA cuenta, así que una key inválida no degrada a las demás.
  def test_connection
    service = Automations::ProvisioningService.new(@account)
    @account_health = service.account_health
    @credential_kind = service.credential_kind

    @config.update(last_status: @account_health.success? ? 'ok' : 'error',
                   last_error: @account_health.success? ? nil : @account_health.error)

    @remote_status = @account_health
    @module_status = service.module_status if @config.enabled?
    # `render :index` no ejecuta la acción index: hay que calcularlo aquí también.
    load_user_selection
    @state = state_service.recalculate!(remote_result: @account_health)
    render :index
  end

  private

  # Si el formato no valida (pegado truncado o con basura) se avisa aquí, en vez de
  # dejar que la plataforma remota responda un 401 opaco.
  def persist_api_key!(success_message)
    if @config.save
      redirect_to super_admin_account_account_automations_path(@account), notice: success_message
    else
      redirect_with_alert('No se pudo guardar la credencial: debe tener el formato jbx_ seguido de 32 caracteres ' \
                          'hexadecimales, tal como la devuelve el panel de Automations.')
    end
  end
  # rubocop:enable Rails/I18nLocaleTexts
end
