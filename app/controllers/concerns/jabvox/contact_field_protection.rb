module Jabvox::ContactFieldProtection
  extend ActiveSupport::Concern

  JABVOX_MASKED = '***'.freeze

  # param name => masker field name
  TOP_LEVEL_FIELD_MAP = {
    'email' => 'email',
    'phone_number' => 'phone',
    'name' => 'name',
    'identifier' => 'identification',
  }.freeze

  ADDITIONAL_ATTR_FIELD_MAP = {
    'jabvox_identification_number' => 'identification',
    'jabvox_contact_type' => 'contact_type',
    'company_name' => 'company',
    'country' => 'country',
    'country_code' => 'country',
    'city' => 'city',
    'description' => nil,
  }.freeze

  SOCIAL_FIELD_MAP = {
    'facebook' => 'social_facebook',
    'twitter' => 'social_twitter',
    'linkedin' => 'social_linkedin',
    'github' => 'social_github',
    'telegram' => 'social_telegram',
    'tiktok' => 'social_tiktok',
  }.freeze

  included do
    before_action :jabvox_strip_masked_params, only: [:update]
  end

  private

  def jabvox_strip_masked_params
    TOP_LEVEL_FIELD_MAP.each do |param_key, mask_field|
      val = params[param_key]
      next unless val == JABVOX_MASKED || (val.blank? && mask_field && !jabvox_field_visible?(mask_field))

      params.delete(param_key)
    end

    attrs = params[:additional_attributes]
    return unless attrs.is_a?(ActionController::Parameters)

    ADDITIONAL_ATTR_FIELD_MAP.each do |attr_key, mask_field|
      val = attrs[attr_key]
      next unless val == JABVOX_MASKED || (val.blank? && mask_field && !jabvox_field_visible?(mask_field))

      attrs.delete(attr_key)
    end

    social = attrs[:social_profiles]
    return unless social.is_a?(ActionController::Parameters)

    SOCIAL_FIELD_MAP.each do |social_key, mask_field|
      val = social[social_key]
      social.delete(social_key) if val == JABVOX_MASKED || (val.blank? && !jabvox_field_visible?(mask_field))
    end
  end
end
