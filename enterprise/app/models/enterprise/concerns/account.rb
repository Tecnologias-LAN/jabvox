module Enterprise::Concerns::Account
  extend ActiveSupport::Concern

  included do
    store_accessor :settings, :conversation_required_attributes

    has_many :sla_policies, dependent: :destroy_async
    has_many :applied_slas, dependent: :destroy_async
    has_many :custom_roles, dependent: :destroy_async
    has_many :agent_capacity_policies, dependent: :destroy_async

    has_many :companies, dependent: :destroy_async
    has_many :calls, dependent: :destroy_async

    has_one :saml_settings, dependent: :destroy_async, class_name: 'AccountSamlSettings'
  end
end
