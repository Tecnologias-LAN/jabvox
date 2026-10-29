module Jabvox::AccountDriveFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_drive_enabled_jabvox? if name.to_s == 'jabvox_drive'

    super
  end

  def enabled_features
    super.merge('jabvox_drive' => jabvox_drive_enabled_jabvox?)
  end

  # ¿Cambió `limits` de forma que la cuota efectiva de almacenamiento AUMENTÓ?
  # (público: lo usa el callback registrado en Account, ver account.rb).
  def drive_quota_increased?
    return false unless jabvox_drive_enabled_jabvox?
    return false unless saved_change_to_attribute?(:limits)

    before, after = saved_change_to_attribute(:limits)
    storage_gb_from(after) > storage_gb_from(before)
  rescue StandardError
    false
  end

  def storage_gb_from(limits_hash)
    (limits_hash || {}).to_h.stringify_keys['storage_gb'].to_i
  end

  def enqueue_drive_regularization
    Jabvox::Drive::QuotaRegularizationJob.perform_later(id)
  rescue StandardError => e
    Rails.logger.error("[jabvox-drive] no se pudo encolar regularización account_id=#{id}: #{e.class}")
  end
end
