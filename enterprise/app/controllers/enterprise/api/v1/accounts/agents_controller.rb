module Enterprise::Api::V1::Accounts::AgentsController
  def create
    super
    associate_agent_with_custom_role
  end

  def update
    super
    associate_agent_with_custom_role
  end

  private

  def associate_agent_with_custom_role
    # Only touch the custom role when the request explicitly includes the key:
    # a PATCH that doesn't mention custom_role_id must not silently clear it.
    return unless params.key?(:custom_role_id)

    # Scope to the account so a foreign account's role id can never be attached.
    role_id = params[:custom_role_id].presence && Current.account.custom_roles.find(params[:custom_role_id]).id
    @agent.current_account_user.update!(custom_role_id: role_id)
  end
end
