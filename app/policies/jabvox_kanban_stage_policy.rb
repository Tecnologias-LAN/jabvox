class JabvoxKanbanStagePolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_kanban_manage') || false
  end

  def index?
    @account_user.administrator? || @account_user.agent?
  end

  def show?
    @account_user.administrator? || @account_user.agent?
  end

  def create?
    can_manage?
  end

  def update?
    can_manage?
  end

  def destroy?
    can_manage?
  end
end
