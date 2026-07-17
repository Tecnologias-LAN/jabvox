module Enterprise::AccountUser
  # A user with a custom role is still, at its base, the account_user's role
  # (agent/administrator). We include that base role alongside the custom-role
  # permissions and the 'custom_role' marker so the frontend route guard always
  # lets them reach the agent-level base routes (dashboard, conversations). Without
  # the base role, a custom role that only grants Jabvox permissions left the user
  # unable to access ANY base route → the router redirect-looped ("página no
  # responde"). Fine-grained authorization still happens per-endpoint in the
  # backend policies. De-duplicated so the array never carries repeats.
  def permissions
    return super if custom_role.blank?

    (custom_role.permissions + ['custom_role', base_role_permission]).uniq
  end

  private

  def base_role_permission
    administrator? ? 'administrator' : 'agent'
  end
end
