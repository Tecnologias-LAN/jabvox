# frozen_string_literal: true

# CDR del PBX materializado localmente + enriquecido (ver CreateJabvoxCdrRecords).
# El reporte lee de esta tabla para filtrar/paginar exacto a cualquier volumen.
# == Schema Information
#
# Table name: jabvox_cdr_records
#
#  id              :bigint           not null, primary key
#  agent_extension :string
#  agent_name      :string
#  billsec         :integer          default(0)
#  calldate        :datetime         not null
#  channel         :string
#  destination     :string
#  disposition     :string
#  dst             :string
#  dstchannel      :string
#  duration        :integer          default(0)
#  linkedid        :string
#  medium          :string
#  origin          :string
#  origin_channel  :string
#  recordingfile   :string
#  src             :string
#  typification    :string
#  uniqueid        :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  account_id      :bigint           not null
#  typification_id :bigint
#
# Indexes
#
#  idx_cdr_records_account_agent_ext        (account_id,agent_extension)
#  idx_cdr_records_account_calldate         (account_id,calldate)
#  idx_cdr_records_account_calldate_keyset  (account_id,calldate DESC,id DESC)
#  idx_cdr_records_account_disposition      (account_id,disposition)
#  idx_cdr_records_account_medium           (account_id,medium)
#  idx_cdr_records_account_typ              (account_id,typification_id)
#  idx_cdr_records_account_uniqueid         (account_id,uniqueid) UNIQUE
#  index_jabvox_cdr_records_on_account_id   (account_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class JabvoxCdrRecord < ApplicationRecord
  self.table_name = 'jabvox_cdr_records'

  belongs_to :account

  # Medios de la llamada. El 'dialer' incluye TANTO las salientes del marcador COMO
  # las entrantes del proveedor hacia el agente (no se distingue dirección).
  MEDIUMS = %w[dialer click_to_call manual].freeze
  DISPOSITIONS = ['ANSWERED', 'NO ANSWER', 'BUSY', 'FAILED'].freeze

  scope :for_account, ->(account_id) { where(account_id: account_id) }
  scope :recent_first, -> { order(calldate: :desc) }
end
