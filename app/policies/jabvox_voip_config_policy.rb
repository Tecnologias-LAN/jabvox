class JabvoxVoipConfigPolicy < ApplicationPolicy
  def can_manage?
    @account_user.administrator? ||
      @account_user.custom_role&.grants?('jabvox_voip_manage') || false
  end

  def show?
    can_manage?
  end

  def update?
    can_manage?
  end

  def status?
    can_manage?
  end

  def originate?
    @account_user.administrator? || @account_user.agent?
  end
end
