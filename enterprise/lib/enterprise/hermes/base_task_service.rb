module Enterprise::Hermes::BaseTaskService
  def perform
    return { error: I18n.t('captain.copilot_limit'), error_code: 429 } if counts_toward_usage? && !responses_available?

    unless ai_tasks_enabled?
      return { error: I18n.t('captain.upgrade') } if JabvoxApp.jabvox_cloud?

      return { error: I18n.t('captain.disabled') }
    end

    result = super
    increment_usage if counts_toward_usage? && successful_result?(result)
    result
  end

  private

  def responses_available?
    return true unless JabvoxApp.jabvox_cloud?

    account.usage_limits[:captain][:responses][:current_available].positive?
  end

  def successful_result?(result)
    result.is_a?(Hash) && result[:message].present? && !result[:error]
  end

  def increment_usage
    Rails.logger.info("[HERMES][#{self.class.name}] Incrementing response usage for account #{account.id}")
    account.increment_response_usage
  end
end
