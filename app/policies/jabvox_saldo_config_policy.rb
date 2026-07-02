class JabvoxSaldoConfigPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_saldo_manage') || false
  end

  def show?
    can_manage?
  end

  def update?
    can_manage?
  end

  def status?
    @account_user.administrator? || @account_user.agent?
  end
end
