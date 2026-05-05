module Jabvox::AccountKanbanFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_kanban_enabled_jabvox? if name.to_s == 'jabvox_kanban'

    super
  end

  def enabled_features
    super.merge('jabvox_kanban' => jabvox_kanban_enabled_jabvox?)
  end
end
