# Scheduled service: advances task cards whose stage has a time-based automation
# (move_after_hours / move_if_inactive). Moving a card updates its stage_id, which fires
# that stage's own automations via the model's after_commit hook.
class Jabvox::TaskTimeAutomationsService
  def perform
    JabvoxTaskStageAutomation
      .active
      .where(automation_type_jabvox: %w[move_after_hours move_if_inactive])
      .where.not(target_stage_id: nil)
      .where('trigger_value_jabvox IS NOT NULL OR trigger_hours_jabvox IS NOT NULL')
      .includes(:account, :target_stage)
      .find_each { |auto| process(auto) }
  end

  private

  def process(auto)
    # La cuenta no se da por supuesta a partir de la etapa: se filtra explícitamente. Así,
    # aunque una automatización antigua apunte a una etapa de otra cuenta, no puede arrastrar
    # tareas ajenas. La validación del modelo impide crear nuevas así; esto cubre las ya
    # guardadas.
    return unless auto.account&.feature_enabled?('jabvox_tasks')
    return unless auto.target_stage&.account_id == auto.account_id

    # `trigger_cutoff` respeta la unidad elegida (minutos u horas). Antes se asumían horas
    # siempre, así que una automatización de 30 minutos esperaba 30 horas.
    cutoff = auto.trigger_cutoff
    return if cutoff.blank?

    JabvoxTask
      .where(account_id: auto.account_id, stage_id: auto.stage_id, status_jabvox: 'open',
             deleted_at_jabvox: nil)
      .where(updated_at: ..cutoff)
      .find_each do |task|
      task.update!(stage_id: auto.target_stage_id)
    rescue StandardError => e
      Rails.logger.error("[TaskTimeAutomations] auto=#{auto.id} task=#{task.id} error=#{e.message}")
    end
  end
end
