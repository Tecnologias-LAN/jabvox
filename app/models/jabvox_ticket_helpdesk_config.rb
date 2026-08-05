# Configuración del helpdesk central de tickets: designa la cuenta gestora (cuyos
# administradores ven/gestionan todos los tickets y cuyos agentes ven los asignados)
# y el modo de asignación automática. Es un singleton lógico (a lo sumo una config
# activa a la vez); el super admin la administra.
# == Schema Information
#
# Table name: jabvox_ticket_helpdesk_configs
#
#  id                         :bigint           not null, primary key
#  active_jabvox              :boolean          default(TRUE), not null
#  auto_assign_mode_jabvox    :integer          default("manual"), not null
#  business_hours_jabvox      :jsonb            not null
#  resolver_visibility_jabvox :integer          default("assigned_only"), not null
#  settings_jabvox            :jsonb            not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :integer          not null
#
# Indexes
#
#  idx_ticket_helpdesk_account  (account_id) UNIQUE
#
class JabvoxTicketHelpdeskConfig < ApplicationRecord
  self.table_name = 'jabvox_ticket_helpdesk_configs'

  belongs_to :account

  enum auto_assign_mode_jabvox: { manual: 0, round_robin: 1, by_category: 2 }, _prefix: :auto_assign
  # Visibilidad del resolver (agente de la gestora): assigned_only ve solo lo suyo;
  # full_inbox ve la bandeja completa de la cuenta gestora.
  enum resolver_visibility_jabvox: { assigned_only: 0, full_inbox: 1 }, _prefix: :resolver_visibility

  validates :account_id, uniqueness: true

  # Atajo semántico para la policy: ¿el resolver ve la bandeja completa?
  def resolver_full_visibility?
    resolver_visibility_full_inbox?
  end

  scope :active, -> { where(active_jabvox: true) }

  # La config activa vigente (la cuenta gestora del helpdesk), o nil si no hay.
  def self.current
    active.order(created_at: :desc).first
  end

  # Cuenta gestora activa, o nil.
  def self.manager_account
    current&.account
  end
end
