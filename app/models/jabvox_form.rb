# == Schema Information
#
# Table name: jabvox_forms
#
#  id                        :bigint           not null, primary key
#  active_jabvox             :boolean          default(TRUE), not null
#  fields_jabvox             :jsonb
#  footer_jabvox             :jsonb
#  header_jabvox             :jsonb
#  name_jabvox               :string           not null
#  slug_jabvox               :string           not null
#  submit_actions_jabvox     :jsonb
#  submit_button_text_jabvox :string           default("Enviar")
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#
# Indexes
#
#  index_jabvox_forms_on_account_id   (account_id)
#  index_jabvox_forms_on_slug_jabvox  (slug_jabvox) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxForm < ApplicationRecord
  self.table_name = 'jabvox_forms'

  FIELD_TYPES = %w[text email phone textarea select cedula pais].freeze
  MAX_FIELDS = 30

  belongs_to :account
  has_many :jabvox_form_submissions, dependent: :destroy

  before_validation :generate_slug, on: :create

  validates :name_jabvox, presence: true, length: { maximum: 80 }
  validates :slug_jabvox, presence: true, uniqueness: true,
                          format: { with: /\A[a-z0-9-]+\z/, message: 'only lowercase letters, numbers and hyphens' }
  validate :fields_structure_valid
  validate :within_account_limit, on: :create

  scope :active, -> { where(active_jabvox: true) }
  scope :ordered, -> { order(created_at: :desc) }

  private

  def generate_slug
    return if slug_jabvox.present?

    base = name_jabvox.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/^-|-$/, '')
    base = 'form' if base.blank?
    candidate = base
    counter = 1
    while JabvoxForm.exists?(slug_jabvox: candidate)
      candidate = "#{base}-#{counter}"
      counter += 1
    end
    self.slug_jabvox = candidate
  end

  def fields_structure_valid
    return unless fields_jabvox.is_a?(Array)

    fields_jabvox.reject! { |f| !f.is_a?(Hash) || f['label'].blank? }
    fields_jabvox.each_with_index do |field, idx|
      errors.add(:fields_jabvox, "field #{idx + 1} has invalid type") unless field['type'].in?(FIELD_TYPES)
    end
  end

  def within_account_limit
    config = account.jabvox_form_config
    limit = config&.max_forms_jabvox || 10
    errors.add(:base, 'Form limit reached for this account') if account.jabvox_forms.count >= limit
  end
end
