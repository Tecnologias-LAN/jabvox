module Jabvox::AccountSaldoFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_saldo_enabled_jabvox? if name.to_s == 'jabvox_saldo'

    super
  end

  def enabled_features
    super.merge('jabvox_saldo' => jabvox_saldo_enabled_jabvox?)
  end
end
