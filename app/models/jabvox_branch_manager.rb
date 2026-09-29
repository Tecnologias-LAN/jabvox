# frozen_string_literal: true

# Responsable de una sede. Es informativo: sirve para saber a quién acudir, no concede
# permisos sobre las citas de esa sede.
# == Schema Information
#
# Table name: jabvox_branch_managers
#
#  id         :bigint           not null, primary key
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  branch_id  :bigint           not null
#  user_id    :bigint           not null
#
# Indexes
#
#  index_jabvox_branch_managers_on_branch_id_and_user_id  (branch_id,user_id) UNIQUE
#  index_jabvox_branch_managers_on_user_id                (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (branch_id => jabvox_branches.id)
#  fk_rails_...  (user_id => users.id)
#
class JabvoxBranchManager < ApplicationRecord
  self.table_name = 'jabvox_branch_managers'

  belongs_to :branch, class_name: 'JabvoxBranch'
  belongs_to :user

  validates :user_id, uniqueness: { scope: :branch_id }
  validate :user_belongs_to_branch_account

  private

  def user_belongs_to_branch_account
    return if branch.nil? || user_id.blank?
    return if AccountUser.exists?(account_id: branch.account_id, user_id: user_id)

    errors.add(:user, 'no pertenece a la cuenta de esta sede')
  end
end
