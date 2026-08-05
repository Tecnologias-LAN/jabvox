# Autorización de tickets del helpdesk central. Dos capas:
#   1) Scope: filtra el listado — staff/resolver de la cuenta gestora ven según su
#      rol; el resto solo sus propios tickets (requester_id == usuario actual).
#   2) Por acción: nadie ve/toca tickets ajenos aunque llame la API directamente.
class JabvoxTicketPolicy < ApplicationPolicy
  class Scope
    attr_reader :user_context, :user, :scope

    def initialize(user_context, scope)
      @user_context = user_context
      @user = user_context[:user]
      @scope = scope
    end

    def resolve
      resolver = Jabvox::TicketPermissionResolver.new(user)
      base = scope.kept
      return base.all if resolver.staff? || resolver.resolver_sees_all?
      return base.where(assignee_id: user.id).or(base.where(requester_id: user.id)) if resolver.resolver?

      base.where(requester_id: user.id)
    end
  end

  def index?
    true
  end

  def create?
    true
  end

  def show?
    permission.staff? || permission.resolver_sees_all? || owner? || assigned?
  end

  def update?
    resolver_over_record?
  end

  def assign?
    resolver_over_record?
  end

  def change_status?
    resolver_over_record?
  end

  def resolve?
    resolver_over_record?
  end

  def reopen?
    resolver_over_record?
  end

  # Solo el solicitante califica su propio ticket.
  def rate?
    owner?
  end

  def destroy?
    permission.manager?
  end

  def metrics?
    permission.staff?
  end

  private

  def permission
    @permission ||= Jabvox::TicketPermissionResolver.new(user)
  end

  def owner?
    record.requester_id == user.id
  end

  def assigned?
    record.assignee_id.present? && record.assignee_id == user.id
  end

  # Staff gestiona cualquiera; resolver con bandeja completa también; un resolver
  # normal solo los asignados a él.
  def resolver_over_record?
    return true if permission.staff? || permission.resolver_sees_all?

    permission.resolver? && assigned?
  end
end
