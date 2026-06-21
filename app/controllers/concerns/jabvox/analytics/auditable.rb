# Controller helper to write an audit row scoped to the current account/user/request.
module Jabvox::Analytics::Auditable
  extend ActiveSupport::Concern

  private

  def audit!(action:, result: 'success', auditable: nil, metadata: {})
    Jabvox::Analytics::AuditService
      .new(account: Current.account, user: current_user, request: request)
      .record(action: action, result: result, auditable: auditable, metadata: metadata)
  end
end
