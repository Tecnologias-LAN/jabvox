# == Schema Information
#
# Table name: automation_rules
#
#  id          :bigint           not null, primary key
#  actions     :jsonb            not null
#  active      :boolean          default(TRUE), not null
#  conditions  :jsonb            not null
#  description :text
#  event_name  :string           not null
#  name        :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#
# Indexes
#
#  index_automation_rules_on_account_id  (account_id)
#
class AutomationRule < ApplicationRecord
  include Rails.application.routes.url_helpers
  include Reauthorizable
  include Jabvox::AccountResourceLimit

  belongs_to :account
  has_many_attached :files

  # Cuota por cuenta (paquete): nº de reglas de automatización.
  jabvox_resource_limit :automation_rules

  validate :json_conditions_format
  validate :json_actions_format
  validate :query_operator_presence
  validate :query_operator_value
  validates :account_id, presence: true

  after_update_commit :reauthorized!, if: -> { saved_change_to_conditions? }

  scope :active, -> { where(active: true) }

  def conditions_attributes
    %w[content email country_code status message_type browser_language assignee_id team_id referer city company_name inbox_id
       mail_subject phone_number priority conversation_language labels private_note current_time attachment_type]
  end

  def actions_attributes
    %w[send_message add_label remove_label send_email_to_team assign_team assign_agent remove_assigned_agent
       remove_assigned_team send_webhook_event mute_conversation send_attachment change_status resolve_conversation
       open_conversation pending_conversation snooze_conversation change_priority send_email_transcript
       add_private_note].freeze
  end

  def file_base_data
    files.map do |file|
      {
        id: file.id,
        automation_rule_id: id,
        file_type: file.content_type,
        account_id: account_id,
        file_url: url_for(file),
        blob_id: file.blob_id,
        filename: file.filename.to_s
      }
    end
  end

  private

  # Una condición puede ser plana o un GRUPO ({ type: 'group', conditions: [...] }).
  # flattened_conditions aplana los grupos para validar sus hijas como si fueran
  # condiciones de primer nivel (mantiene la retrocompatibilidad con el array plano).
  def flattened_conditions
    (conditions || []).flat_map do |obj|
      group_condition?(obj) ? (obj['conditions'] || obj[:conditions] || []) : [obj]
    end
  end

  def group_condition?(obj)
    obj.is_a?(Hash) && (obj['type'].to_s == 'group' || obj[:type].to_s == 'group')
  end

  def json_conditions_format
    return if conditions.blank?

    attributes = flattened_conditions.map { |obj| obj['attribute_key'] } # rubocop:disable Rails/Pluck
    unsupported = attributes - conditions_attributes
    unsupported -= account.custom_attribute_definitions.pluck(:attribute_key)
    errors.add(:conditions, "Automation conditions #{unsupported.join(',')} not supported.") if unsupported.any?
  end

  def json_actions_format
    return if actions.blank?

    attributes = actions.map { |obj, _| obj['action_name'] }
    actions = attributes - actions_attributes

    errors.add(:actions, "Automation actions #{actions.join(',')} not supported.") if actions.any?
  end

  def query_operator_presence
    return if conditions.blank?

    # A nivel raíz solo la última condición/grupo puede ir sin query_operator.
    root_dangling = conditions.count { |obj| obj['query_operator'].nil? }
    errors.add(:conditions, 'Automation conditions should have query operator.') if root_dangling > 1

    # Dentro de cada grupo, igual: solo su última hija puede ir sin operador.
    errors.add(:conditions, 'Group conditions should have query operator.') if any_group_with_dangling_operators?
  end

  def any_group_with_dangling_operators?
    conditions.any? do |obj|
      group_condition?(obj) && group_children_of(obj).count { |child| child['query_operator'].nil? } > 1
    end
  end

  def group_children_of(obj)
    obj['conditions'] || obj[:conditions] || []
  end

  # This validation ensures logical operators are being used correctly in automation conditions.
  # And we don't push any unsanitized query operators to the database.
  def query_operator_value
    flattened_conditions.each do |obj|
      validate_single_condition(obj)
    end
    # También valida el operador del grupo en sí.
    (conditions || []).each { |obj| validate_single_condition(obj) if group_condition?(obj) }
  end

  def validate_single_condition(condition)
    query_operator = condition['query_operator']

    return if query_operator.nil?
    return if query_operator.empty?

    operator = query_operator.upcase
    errors.add(:conditions, 'Query operator must be either "AND" or "OR"') unless %w[AND OR].include?(operator)
  end
end

AutomationRule.include_mod_with('Audit::AutomationRule')
AutomationRule.prepend_mod_with('AutomationRule')
