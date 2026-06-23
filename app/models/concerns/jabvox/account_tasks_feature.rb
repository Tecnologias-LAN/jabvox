module Jabvox::AccountTasksFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_tasks_enabled_jabvox? if name.to_s == 'jabvox_tasks'

    super
  end

  def enabled_features
    super.merge('jabvox_tasks' => jabvox_tasks_enabled_jabvox?)
  end
end
