# == Schema Information
#
# Table name: jabvox_email_templates
#
#  id            :bigint           not null, primary key
#  active        :boolean          default(TRUE), not null
#  body          :text
#  name          :string           not null
#  subject       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  account_id    :bigint           not null
#  created_by_id :bigint
#
# Indexes
#
#  index_jabvox_email_templates_on_account_id           (account_id)
#  index_jabvox_email_templates_on_account_id_and_name  (account_id,name) UNIQUE
#  index_jabvox_email_templates_on_created_by_id        (created_by_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#
class JabvoxEmailTemplate < ApplicationRecord
  belongs_to :account

  # Automations that send this template simply lose it (send nothing) instead
  # of blocking the deletion.
  has_many :kanban_stage_automations, class_name: 'JabvoxKanbanStageAutomation',
                                      foreign_key: :jabvox_email_template_id,
                                      dependent: :nullify, inverse_of: false
  has_many :task_automations, class_name: 'JabvoxTaskAutomation',
                              foreign_key: :email_template_id,
                              dependent: :nullify, inverse_of: false
  has_many :task_stage_automations, class_name: 'JabvoxTaskStageAutomation',
                                    foreign_key: :email_template_id,
                                    dependent: :nullify, inverse_of: false

  validates :name, presence: true, uniqueness: { scope: :account_id }
  validates :subject, presence: true
  validates :body, length: { maximum: 5_000_000 }, allow_nil: true

  scope :active, -> { where(active: true) }

  def self.limit_for(account)
    limit = account.effective_limit_for(:email_templates)
    limit.positive? ? limit : 20
  end

  def self.within_limit?(account)
    account.jabvox_email_templates.count < limit_for(account)
  end
end
