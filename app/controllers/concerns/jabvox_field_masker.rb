module JabvoxFieldMasker
  extend ActiveSupport::Concern

  included do
    helper_method :jabvox_field_visible?, :jabvox_mask, :jabvox_mask_attrs
  end

  private

  def jabvox_field_vis
    @jabvox_field_vis ||= begin
      return JabvoxFieldVisibility::FIELDS.index_with { true } unless current_user && Current.account

      records = Current.account.jabvox_field_visibilities.where(user_id: current_user.id)
      JabvoxFieldVisibility::FIELDS.index_with { true }.merge(
        records.each_with_object({}) { |v, h| h[v.field_name] = v.can_view }
      )
    end
  end

  def jabvox_field_visible?(field)
    jabvox_field_vis[field.to_s] != false
  end

  def jabvox_mask(field, value)
    jabvox_field_visible?(field) ? value : '***'
  end

  def jabvox_mask_attrs(attrs)
    a = (attrs || {}).dup

    a['jabvox_identification_number'] = '***' unless jabvox_field_visible?('identification')
    a['jabvox_contact_type']          = '***' unless jabvox_field_visible?('contact_type')
    a['company_name']                 = '***' unless jabvox_field_visible?('company')
    a['country']                      = '***' unless jabvox_field_visible?('country')
    a['country_code']                 = '***' unless jabvox_field_visible?('country')
    a['city']                         = '***' unless jabvox_field_visible?('city')

    social = (a['social_profiles'] || {}).dup
    social['facebook']  = '***' unless jabvox_field_visible?('social_facebook')
    social['twitter']   = '***' unless jabvox_field_visible?('social_twitter')
    social['linkedin']  = '***' unless jabvox_field_visible?('social_linkedin')
    social['github']    = '***' unless jabvox_field_visible?('social_github')
    social['telegram']  = '***' unless jabvox_field_visible?('social_telegram')
    social['tiktok']    = '***' unless jabvox_field_visible?('social_tiktok')
    a['social_profiles'] = social

    a
  end
end
