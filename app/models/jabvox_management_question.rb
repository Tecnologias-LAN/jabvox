# == Schema Information
#
# Table name: jabvox_management_questions
#
#  id                         :bigint           not null, primary key
#  label                      :string           not null
#  lead_field                 :string           default(""), not null
#  lead_field_locked          :boolean          default(FALSE), not null
#  options                    :jsonb            not null
#  position                   :integer          default(0), not null
#  question_key               :string
#  question_type              :string           default("text"), not null
#  required                   :boolean          default(FALSE), not null
#  visibility                 :jsonb            not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  account_id                 :bigint           not null
#  created_by_id              :bigint
#  jabvox_management_state_id :bigint           not null
#
# Indexes
#
#  idx_mgmt_questions_account_question_key                (account_id,question_key)
#  idx_on_jabvox_management_state_id_5c2de1c51d           (jabvox_management_state_id)
#  idx_on_jabvox_management_state_id_position_5047167b84  (jabvox_management_state_id,position)
#  index_jabvox_management_questions_on_account_id        (account_id)
#  index_jabvox_management_questions_on_created_by_id     (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (jabvox_management_state_id => jabvox_management_states.id)
#
class JabvoxManagementQuestion < ApplicationRecord
  self.table_name = 'jabvox_management_questions'

  # text/number/date  -> free input      boolean -> yes/no
  # list              -> pick ONE option  multiselect -> pick MANY options
  QUESTION_TYPES = %w[text number date boolean list multiselect].freeze
  # Types whose answers are chosen from `options`.
  OPTION_TYPES = %w[list multiselect].freeze
  # Conditional-visibility rule vocabulary.
  VISIBILITY_LOGICS = %w[and or].freeze
  VISIBILITY_OPERATORS = %w[equals not_equals includes answered].freeze
  MAX_VISIBILITY_RULES = 10
  # Allowed namespaces for lead_field autofill mapping. The suffix after the
  # prefix is a field/attribute key resolved client-side against the lead.
  LEAD_FIELD_PREFIXES = %w[contact. lead.].freeze

  belongs_to :account
  belongs_to :management_state, class_name: 'JabvoxManagementState',
                                foreign_key: :jabvox_management_state_id, inverse_of: :questions
  has_many :answers, class_name: 'JabvoxManagementAnswer', dependent: :nullify, inverse_of: :question

  before_validation :inherit_account
  before_validation :normalize_visibility
  before_validation :normalize_lead_field
  before_validation :assign_question_key

  # Stable key for "the same logical question" across every management state,
  # derived from the label. Two questions with the same label (e.g. "¿Gestionado?"
  # in different states) share the same question_key, so an external CRM can map
  # once per key instead of per (per-state) id. Accent/case/punctuation-insensitive.
  #   "¿Gestionado?" -> "gestionado" ; "Próxima Llamada" -> "proxima_llamada"
  def self.slugify_label(text)
    s = text.to_s.unicode_normalize(:nfkd).encode('ASCII', replace: '') # strip accents
    s = s.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_+|_+\z/, '')
    s.presence
  end

  validates :label, presence: true, length: { maximum: 250 }
  validates :question_type, inclusion: { in: QUESTION_TYPES }
  validates :lead_field, length: { maximum: 250 }
  validate :options_present_for_option_types
  validate :visibility_well_formed

  scope :ordered, -> { order(:position) }

  # True when this question has no visibility rules (always shown).
  def unconditional?
    visibility.blank? || Array(visibility['rules']).empty?
  end

  private

  def inherit_account
    self.account_id ||= management_state&.account_id
  end

  # Keep question_key in sync with the label (unless it was set explicitly and the
  # label hasn't changed). Recomputed whenever the label changes so the key stays
  # meaningful; falls back to "campo" when the label has no slug-able characters.
  def assign_question_key
    return if question_key.present? && !label_changed?

    self.question_key = self.class.slugify_label(label) || 'campo'
  end

  # Coerce visibility into a clean {logic, rules[]} hash, dropping junk. This
  # runs before validation so both the API and the import path get the same
  # normalized shape and the same rejection of malformed rules.
  def normalize_visibility
    raw = visibility
    unless raw.is_a?(Hash)
      self.visibility = {}
      return
    end

    logic = raw['logic'].to_s
    logic = 'and' unless VISIBILITY_LOGICS.include?(logic)

    rules = Array(raw['rules']).filter_map { |r| normalize_rule(r) }.first(MAX_VISIBILITY_RULES)

    self.visibility = rules.empty? ? {} : { 'logic' => logic, 'rules' => rules }
  end

  def normalize_rule(rule)
    return nil unless rule.is_a?(Hash)

    question = rule['question'].to_s.strip.first(250)
    operator = rule['operator'].to_s
    operator = 'equals' unless VISIBILITY_OPERATORS.include?(operator)
    return nil if question.blank?

    normalized = { 'question' => question, 'operator' => operator }
    # 'answered' needs no value; the others carry a comparison value.
    normalized['value'] = rule['value'].to_s.first(250) unless operator == 'answered'
    normalized
  end

  # Keep lead_field only when it uses an allowed namespace; anything else is
  # dropped to '' so a junk mapping can never reach the client resolver.
  def normalize_lead_field
    value = lead_field.to_s.strip
    self.lead_field = LEAD_FIELD_PREFIXES.any? { |p| value.start_with?(p) } ? value : ''
  end

  def options_present_for_option_types
    return unless OPTION_TYPES.include?(question_type)

    errors.add(:options, 'must have at least one option') if Array(options).reject(&:blank?).empty?
  end

  # After normalization visibility is always a clean shape, so this guards the
  # remaining semantic rule: a question cannot depend on itself.
  def visibility_well_formed
    return if unconditional?

    Array(visibility['rules']).each do |rule|
      errors.add(:visibility, 'a question cannot depend on itself') if rule['question'] == label
    end
  end
end
