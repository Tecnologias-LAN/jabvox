# frozen_string_literal: true

# Contadores de cuota del Drive por cuenta. Permite reservas atómicas de espacio
# (ver Jabvox::Drive::QuotaService) usando la atomicidad de PostgreSQL, sin
# depender de un lock de Redis para la corrección.
#
# == Schema Information
#
# Table name: jabvox_drive_storage_accounts
#
#  id                 :bigint           not null, primary key
#  last_reconciled_at :datetime
#  overflow_bytes     :bigint           default(0), not null
#  reserved_bytes     :bigint           default(0), not null
#  used_bytes         :bigint           default(0), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#
# Indexes
#
#  index_jabvox_drive_storage_accounts_on_account_id  (account_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxDriveStorageAccount < ApplicationRecord
  belongs_to :account

  validates :account_id, uniqueness: true
  validates :used_bytes, :reserved_bytes, :overflow_bytes,
            numericality: { greater_than_or_equal_to: 0 }

  # Comprometido = lo ya guardado + lo reservado en vuelo. Es lo que cuenta para
  # decidir si una nueva subida cabe en la cuota.
  def committed_bytes
    used_bytes.to_i + reserved_bytes.to_i
  end
end
