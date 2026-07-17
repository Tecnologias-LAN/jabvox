class Contacts::FilterService < FilterService
  ATTRIBUTE_MODEL = 'contact_attribute'.freeze

  def initialize(account, user, params)
    @account = account
    # TODO: Change the order of arguments in FilterService maybe?
    # account, user, params makes more sense
    super(params, user)
  end

  def perform
    validate_query_operator
    @contacts = query_builder(@filters['contacts'])

    {
      contacts: @contacts,
      count: @contacts.count
    }
  end

  def filter_values(query_hash)
    current_val = query_hash['values'][0]
    if query_hash['attribute_key'] == 'phone_number'
      "+#{current_val&.delete('+')}"
    elsif query_hash['attribute_key'] == 'country_code'
      current_val.downcase
    else
      current_val.is_a?(String) ? current_val.downcase : current_val
    end
  end

  def base_relation
    @account.contacts
            .resolved_contacts(use_crm_v2: @account.feature_enabled?('crm_v2'))
            .visible_to(visibility_account_user)
  end

  # The account_user for the filtering user, so agents only filter within the
  # contacts they can see. nil (internal callers) means no restriction.
  def visibility_account_user
    return nil if @user.nil?

    @account.account_users.find_by(user_id: @user.id)
  end

  def filter_config
    {
      entity: 'Contact',
      table_name: 'contacts'
    }
  end

  private

  def equals_to_filter_string(filter_operator, current_index)
    return "= :value_#{current_index}" if filter_operator == 'equal_to'

    "!= :value_#{current_index}"
  end
end
