module Jabvox::AccountProductsFeature
  extend ActiveSupport::Concern

  def feature_enabled?(name)
    return jabvox_products_enabled_jabvox? if name.to_s == 'jabvox_products'

    super
  end

  def enabled_features
    super.merge('jabvox_products' => jabvox_products_enabled_jabvox?)
  end
end
