# frozen_string_literal: true

# Flujo de automatización. El grafo vive en las versiones, no aquí: `current_version`
# apunta a la que se ejecuta.
# == Schema Information
#
# Table name: jabvox_flows
#
#  id                 :bigint           not null, primary key
#  description        :text
#  name               :string           not null
#  status             :integer          default("draft"), not null
#  webhook_token      :string
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  current_version_id :bigint
#  folder_id          :bigint
#
# Indexes
#
#  idx_jabvox_flows_account_folder      (account_id,folder_id)
#  idx_jabvox_flows_account_status      (account_id,status)
#  index_jabvox_flows_on_webhook_token  (webhook_token) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (current_version_id => jabvox_flow_versions.id) ON DELETE => nullify
#  fk_rails_...  (folder_id => jabvox_flow_folders.id) ON DELETE => nullify
#
class JabvoxFlow < ApplicationRecord
  belongs_to :account
  belongs_to :folder, class_name: 'JabvoxFlowFolder', optional: true
  belongs_to :current_version, class_name: 'JabvoxFlowVersion', optional: true
  has_many :versions, class_name: 'JabvoxFlowVersion', foreign_key: :flow_id, dependent: :destroy,
                      inverse_of: :flow
  has_many :runs, class_name: 'JabvoxFlowRun', foreign_key: :flow_id, dependent: :destroy, inverse_of: :flow

  enum :status, { draft: 0, active: 1, paused: 2, archived: 3 }

  validates :name, presence: true
  validate :folder_belongs_to_account

  # Token para el disparador "Webhook entrante": forma la URL pública única del
  # flujo. Se genera al crear y se puede rotar. No es el `secret` del nodo (eso es
  # una verificación adicional opcional dentro del propio payload).
  before_create :ensure_webhook_token

  def regenerate_webhook_token!
    update!(webhook_token: self.class.generate_webhook_token)
  end

  def self.generate_webhook_token
    loop do
      token = SecureRandom.urlsafe_base64(24)
      break token unless exists?(webhook_token: token)
    end
  end

  private

  def ensure_webhook_token
    self.webhook_token ||= self.class.generate_webhook_token
  end

  # Sin esto, un PATCH con el id de una carpeta ajena movería el flujo fuera de
  # su cuenta: la clave foránea apunta a la tabla, no a la cuenta.
  def folder_belongs_to_account
    return if folder_id.blank?
    return if JabvoxFlowFolder.exists?(id: folder_id, account_id: account_id)

    errors.add(:folder, 'no pertenece a esta cuenta')
  end
end
