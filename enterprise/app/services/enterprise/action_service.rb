module Enterprise::ActionService
  # Liga (o desliga) el contacto de la conversación a una EMPRESA (entidad).
  # Pensado para automatizaciones tipo "cliente existente → etiquetar soporte":
  # otra acción de la misma regla añade la etiqueta; esta deja ligado al contacto.
  #
  # Degrada con gracia: si el módulo de empresas está apagado, no es enterprise,
  # o la conversación no tiene contacto, no hace nada. La empresa se busca SIEMPRE
  # dentro de la cuenta (nunca Company.find global) para no cruzar cuentas.
  def assign_company(company_ids = [])
    return unless @account.feature_enabled?('companies') && JabvoxApp.enterprise?

    contact = @conversation.contact
    return if contact.nil?

    value = Array(company_ids).first.to_s
    return Companies::ContactMembershipService.new(company: contact.company).remove(contact: contact) if unassign_company?(value, contact)

    company = @account.companies.find_by(id: value)
    return if company.nil?

    Companies::ContactMembershipService.new(company: company).assign(contact: contact)
  end

  # Desasignar: valor vacío / 'nil' / '0' (opción "Ninguna" del desplegable) y el
  # contacto hoy tiene una empresa ligada. Si ya no tiene, no hay nada que hacer.
  def unassign_company?(value, contact)
    (value.blank? || %w[nil 0].include?(value)) && contact.company_id.present?
  end

  def add_sla(sla_policy_id)
    return if sla_policy_id.blank?

    sla_policy = @account.sla_policies.find_by(id: sla_policy_id.first)
    return if sla_policy.nil?
    return if @conversation.sla_policy.present?
    return unless @conversation.sla_applicable?

    Rails.logger.info "SLA:: Adding SLA #{sla_policy.id} to conversation: #{@conversation.id}"
    @conversation.update!(sla_policy_id: sla_policy.id)
  end
end
