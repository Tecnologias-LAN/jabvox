# Gateo de las secciones de Configuración que antes estaban siempre visibles (lista blanca
# de IP, estados de gestión, seguridad de campos, flujo de conversación, SLA, auditoría y
# respuestas predefinidas).
#
# Van juntas en un solo concern porque comparten exactamente la misma forma —una columna
# booleana por módulo— y siete archivos idénticos solo añadirían ruido.
#
# `audit_logs`, `sla` y `canned_responses` son features de Chatwoot que ya existen en
# features.yml: aquí se les añade un interruptor POR CUENTA que manda sobre el global, de
# modo que apagarlo en una cuenta no afecta a las demás.
module Jabvox::AccountSettingsSectionsFeature
  extend ActiveSupport::Concern

  # feature => columna booleana de la cuenta.
  SECTION_FLAGS = {
    'jabvox_ip_whitelist' => :jabvox_ip_whitelist_enabled_jabvox,
    'jabvox_management_states' => :jabvox_management_states_enabled_jabvox,
    'jabvox_field_security' => :jabvox_field_security_enabled_jabvox,
    'jabvox_conversation_workflow' => :jabvox_conversation_workflow_enabled_jabvox,
    'sla' => :jabvox_sla_enabled_jabvox,
    'audit_logs' => :jabvox_audit_logs_enabled_jabvox,
    'canned_responses' => :jabvox_canned_responses_enabled_jabvox
  }.freeze

  def feature_enabled?(name)
    column = SECTION_FLAGS[name.to_s]
    # Si la columna aún no existe (deploy por delante de su migración), se cae al
    # comportamiento anterior en vez de romper toda la cuenta.
    return super unless column && self.class.column_names.include?(column.to_s)

    # Para las features de Chatwoot (sla, audit_logs, canned_responses) hay que cumplir
    # AMBAS condiciones: el plan/flag global y el interruptor de la cuenta.
    enabled = public_send(column)
    jabvox_only?(name) ? enabled : (enabled && super)
  end

  def enabled_features
    extras = SECTION_FLAGS.filter_map do |name, column|
      next unless self.class.column_names.include?(column.to_s)

      [name, feature_enabled?(name)]
    end.to_h
    super.merge(extras)
  end

  private

  def jabvox_only?(name)
    name.to_s.start_with?('jabvox_')
  end
end
