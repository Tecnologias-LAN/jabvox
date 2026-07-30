# A participant of a WhatsApp group. Members are contacts (not agents), joined by
# invite link. role: admin/member. invite_status tracks the invite lifecycle
# (pending → joined → left/removed), driven by group webhooks.
# == Schema Information
#
# Table name: jabvox_whatsapp_group_members
#
#  id                   :bigint           not null, primary key
#  invite_status_jabvox :string           default("pending"), not null
#  joined_at_jabvox     :datetime
#  left_at_jabvox       :datetime
#  name_jabvox          :string
#  phone_number_jabvox  :string           not null
#  role_jabvox          :string           default("member"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :integer          not null
#  contact_id           :integer
#  whatsapp_group_id    :integer          not null
#
# Indexes
#
#  idx_wa_group_members_group   (whatsapp_group_id)
#  idx_wa_group_members_unique  (whatsapp_group_id,phone_number_jabvox) UNIQUE
#
class JabvoxWhatsappGroupMember < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_group_members'

  ROLES = %w[admin member].freeze
  INVITE_STATUSES = %w[pending joined left removed].freeze

  belongs_to :group, class_name: 'JabvoxWhatsappGroup',
                     foreign_key: :whatsapp_group_id, inverse_of: :members
  belongs_to :account
  belongs_to :contact, optional: true

  validates :phone_number_jabvox, presence: true
  validates :role_jabvox, inclusion: { in: ROLES }
  validates :invite_status_jabvox, inclusion: { in: INVITE_STATUSES }
  validates :phone_number_jabvox, uniqueness: { scope: :whatsapp_group_id }
  # Re-check the group's cap whenever a member is added or reactivated, so the
  # 8-member limit holds even when members are created directly (not via the group).
  validate :group_within_member_limit

  scope :active, -> { where(invite_status_jabvox: JabvoxWhatsappGroup::ACTIVE_MEMBER_STATUSES) }

  private

  def group_within_member_limit
    return unless JabvoxWhatsappGroup::ACTIVE_MEMBER_STATUSES.include?(invite_status_jabvox)
    return if group.blank?

    others = group.members.where(invite_status_jabvox: JabvoxWhatsappGroup::ACTIVE_MEMBER_STATUSES).where.not(id: id).count
    return if others < JabvoxWhatsappGroup::MAX_ACTIVE_MEMBERS

    errors.add(:base, "A WhatsApp group cannot have more than #{JabvoxWhatsappGroup::MAX_ACTIVE_MEMBERS} active members")
  end
end
