class Api::V1::Accounts::Jabvox::BaseController < Api::V1::Accounts::BaseController
  before_action :check_feature_enabled

  # Each Jabvox module controller must be gated by its OWN feature flag, not by
  # a single shared one. Subclasses declare their module flag with:
  #
  #   jabvox_feature 'jabvox_sms'
  #
  # The declared flag flows down inheritance chains via class_attribute, so a
  # controller that inherits from another Jabvox controller keeps the parent's
  # flag unless it overrides it. Controllers that do not declare a flag fall
  # back to the DEFAULT_JABVOX_FEATURE below.
  class_attribute :jabvox_feature_flag, instance_writer: false, default: nil

  DEFAULT_JABVOX_FEATURE = 'jabvox_kanban'.freeze

  def self.jabvox_feature(flag)
    self.jabvox_feature_flag = flag.to_s
  end

  private

  def check_feature_enabled
    flag = self.class.jabvox_feature_flag
    # `jabvox_feature :none` opts a controller out of module gating entirely
    # (e.g. multi-module endpoints gated only by per-action permissions).
    return if flag.to_s == 'none'

    flag = flag.presence || DEFAULT_JABVOX_FEATURE
    return if Current.account.feature_enabled?(flag)

    render json: { error: "Jabvox module is not enabled for this account (#{flag})" },
           status: :forbidden
  end
end
