# Returns the current user's effective Analytics capabilities so the UI can gate features.
class Api::V1::Accounts::Jabvox::Analytics::CapabilitiesController < Api::V1::Accounts::Jabvox::Analytics::BaseController
  def show
    render json: {
      is_admin: permission_resolver.admin?,
      capabilities: capability_map
    }
  end

  private

  def capability_map
    JabvoxAnalyticsPermission::KEYS.index_with { |key| permission_resolver.can?(key) }
  end
end
