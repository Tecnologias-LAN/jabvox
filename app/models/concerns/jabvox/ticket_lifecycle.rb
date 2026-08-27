# Métodos de ciclo de vida del ticket (asignar, cambiar estado, resolver, reabrir).
# Cada transición registra una entrada en jabvox_ticket_activities (bitácora de
# auditoría) y sella los timestamps correspondientes. Extraído del modelo para
# mantenerlo bajo el límite de longitud.
module Jabvox::TicketLifecycle
  extend ActiveSupport::Concern

  # Transiciones válidas de la máquina de estados. Evita saltos inconsistentes
  # (p. ej. closed → in_progress directo). Reabrir pasa por :reopened.
  STATUS_TRANSITIONS = {
    'new_ticket' => %w[assigned in_progress on_hold closed],
    'assigned' => %w[in_progress on_hold new_ticket closed],
    'in_progress' => %w[on_hold resolved assigned closed],
    'on_hold' => %w[in_progress assigned resolved closed],
    'resolved' => %w[closed reopened],
    'closed' => %w[reopened],
    'reopened' => %w[assigned in_progress on_hold resolved closed]
  }.freeze

  class InvalidTransitionError < StandardError; end

  # ¿Es válido el paso status actual → new_status?
  def valid_transition?(new_status)
    return true if status_jabvox.to_s == new_status.to_s

    STATUS_TRANSITIONS.fetch(status_jabvox.to_s, []).include?(new_status.to_s)
  end

  # Asigna el ticket a un agente y lo pasa a 'assigned' si venía nuevo.
  def assign_to!(user, actor: nil)
    prev = assignee_id
    update!(assignee_id: user&.id, status_jabvox: (status_new_ticket? ? :assigned : status_jabvox))
    log_activity!('assigned', from: prev, to: user&.id, actor: actor)
    self
  end

  # Cambia el estado sellando el timestamp que corresponda (resuelto/cerrado).
  # Rechaza transiciones inválidas según la máquina de estados.
  def change_status!(new_status, actor: nil)
    prev = status_jabvox
    return self if prev.to_s == new_status.to_s

    raise InvalidTransitionError, "Transición inválida: #{prev} → #{new_status}" unless valid_transition?(new_status)

    stamp_status_timestamps(new_status)
    update!(status_jabvox: new_status)
    log_activity!('status_changed', from: prev, to: new_status.to_s, actor: actor)
    self
  end

  # Resuelve el ticket con resolución + tipo, sella resolved_at.
  def resolve!(resolution:, resolution_type:, actor: nil)
    prev = status_jabvox
    update!(status_jabvox: :resolved, resolution_jabvox: resolution,
            resolution_type_jabvox: resolution_type, resolved_at_jabvox: Time.current)
    log_activity!('resolved', from: prev, to: 'resolved', actor: actor,
                              metadata: { resolution_type: resolution_type })
    self
  end

  # Reabre un ticket resuelto/cerrado, limpia sellos de cierre e incrementa contador.
  def reopen!(actor: nil)
    prev = status_jabvox
    update!(status_jabvox: :reopened, resolved_at_jabvox: nil, closed_at_jabvox: nil,
            reopened_count_jabvox: reopened_count_jabvox + 1)
    log_activity!('reopened', from: prev, to: 'reopened', actor: actor)
    self
  end

  # Registra la encuesta de satisfacción del solicitante.
  def rate!(rating:, comment: nil, actor: nil)
    update!(satisfaction_rating_jabvox: rating, satisfaction_comment_jabvox: comment)
    log_activity!('rated', to: rating.to_s, actor: actor)
    self
  end

  # Escribe una entrada en la bitácora de auditoría del ticket.
  def log_activity!(action, from: nil, to: nil, actor: nil, metadata: {})
    activities.create!(user_id: actor&.id, action_jabvox: action,
                       from_value_jabvox: from&.to_s, to_value_jabvox: to&.to_s,
                       metadata_jabvox: metadata)
  end

  private

  def stamp_status_timestamps(new_status)
    case new_status.to_s
    when 'resolved' then self.resolved_at_jabvox ||= Time.current
    when 'closed' then self.closed_at_jabvox ||= Time.current
    end
  end
end
