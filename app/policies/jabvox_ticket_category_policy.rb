# Categorías/temas de tickets: cualquier usuario del helpdesk las lee (para el
# formulario de registro); solo un manager (staff) las administra.
class JabvoxTicketCategoryPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :scope

    def initialize(user_context, scope)
      @user_context = user_context
      @scope = scope
    end

    def resolve
      scope.all
    end
  end

  def index?
    true
  end

  def show?
    true
  end

  def create?
    manager?
  end

  def update?
    manager?
  end

  def destroy?
    manager?
  end

  private

  def manager?
    Jabvox::TicketPermissionResolver.new(user).manager?
  end
end
