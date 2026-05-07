# == Schema Information
#
# Table name: jabvox_response_bot_configs
#
#  id                          :bigint           not null, primary key
#  active_labels_jabvox        :jsonb
#  description_jabvox          :text
#  enabled_jabvox              :boolean          default(FALSE), not null
#  name_jabvox                 :string
#  created_at                  :datetime         not null
#  updated_at                  :datetime         not null
#  account_id                  :bigint           not null
#  inbox_id                    :bigint           not null
#  jabvox_ai_chat_model_id     :bigint
#  jabvox_audio_model_id       :bigint
#  jabvox_response_bot_role_id :bigint
#  jabvox_response_bot_seat_id :bigint
#
# Indexes
#
#  idx_on_jabvox_response_bot_seat_id_b150b81444                 (jabvox_response_bot_seat_id)
#  idx_response_bot_configs_account_inbox                        (account_id,inbox_id) UNIQUE
#  idx_response_bot_configs_audio_model                          (jabvox_audio_model_id)
#  idx_response_bot_configs_role                                 (jabvox_response_bot_role_id)
#  index_jabvox_response_bot_configs_on_inbox_id                 (inbox_id)
#  index_jabvox_response_bot_configs_on_jabvox_ai_chat_model_id  (jabvox_ai_chat_model_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (inbox_id => inboxes.id)
#  fk_rails_...  (jabvox_ai_chat_model_id => jabvox_ai_chat_models.id)
#  fk_rails_...  (jabvox_audio_model_id => jabvox_ai_chat_models.id)
#  fk_rails_...  (jabvox_response_bot_role_id => jabvox_response_bot_roles.id)
#  fk_rails_...  (jabvox_response_bot_seat_id => jabvox_response_bot_seats.id)
#
class JabvoxResponseBotConfig < ApplicationRecord
  LABEL_CATEGORIES = %w[proceso_venta proceso_pago quejas_y_reclamos soporte].freeze

  belongs_to :account
  belongs_to :inbox
  belongs_to :jabvox_response_bot_seat, optional: true
  belongs_to :jabvox_response_bot_role, optional: true
  belongs_to :jabvox_ai_chat_model, optional: true
  belongs_to :jabvox_audio_model, class_name: 'JabvoxAiChatModel', optional: true

  validates :inbox_id, uniqueness: { scope: :account_id }

  scope :enabled, -> { where(enabled_jabvox: true) }
end
