class JabvoxVoipConfigPolicy < ApplicationPolicy
  def show?
    @account_user.administrator?
  end

  def update?
    @account_user.administrator?
  end

  def status?
    @account_user.administrator?
  end

  def originate?
    @account_user.administrator? || @account_user.agent?
  end
end
