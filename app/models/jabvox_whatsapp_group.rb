# A WhatsApp group created through Meta's Groups API. Small collaborative room
# (max 8 members, invite-only) — NOT a broadcast. Distinct from bulk WhatsApp
# (1→N) and from 1:1 conversations. Lives on a whatsapp_cloud inbox and, once
# provisioned by Meta, carries the provider_group_id used to send/receive.
# == Schema Information
#
# Table name: jabvox_whatsapp_groups
#
#  id                       :bigint           not null, primary key
#  avatar_url_jabvox        :string
#  description_jabvox       :text
#  invite_link_jabvox       :text
#  metadata_jabvox          :jsonb            not null
#  name_jabvox              :string           not null
#  provider_group_id_jabvox :string
#  status_jabvox            :string           default("active"), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  account_id               :integer          not null
#  conversation_id          :integer
#  created_by_id            :integer
#  inbox_id                 :integer          not null
#
# Indexes
#
#  idx_wa_groups_account      (account_id)
#  idx_wa_groups_inbox        (inbox_id)
#  idx_wa_groups_provider_id  (provider_group_id_jabvox) UNIQUE WHERE (provider_group_id_jabvox IS NOT NULL)
#
class JabvoxWhatsappGroup < ApplicationRecord
  self.table_name = 'jabvox_whatsapp_groups'

  MAX_ACTIVE_MEMBERS = 8
  STATUSES = %w[draft active archived].freeze
  ACTIVE_MEMBER_STATUSES = %w[pending joined].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :conversation, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :members, class_name: 'JabvoxWhatsappGroupMember',
                     foreign_key: :whatsapp_group_id, dependent: :destroy, inverse_of: :group

  validates :name_jabvox, presence: true
  validates :status_jabvox, inclusion: { in: STATUSES }
  validate :active_members_within_limit

  scope :active, -> { where(status_jabvox: 'active') }

  def active_members_count
    members.where(invite_status_jabvox: ACTIVE_MEMBER_STATUSES).count
  end

  def provisioned?
    provider_group_id_jabvox.present?
  end

  private

  # Enforce Meta's hard cap of 8 participants per group at the DB layer, so no
  # path (API, webhook backfill, n8n) can ever push a group past the limit.
  def active_members_within_limit
    return if active_members_count <= MAX_ACTIVE_MEMBERS

    errors.add(:base, "A WhatsApp group cannot have more than #{MAX_ACTIVE_MEMBERS} active members")
  end
end
