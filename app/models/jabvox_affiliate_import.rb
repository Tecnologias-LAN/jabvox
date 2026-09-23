# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_affiliate_imports
#
#  id                   :bigint           not null, primary key
#  campaign_name_jabvox :string
#  completed_at         :datetime
#  country_jabvox       :string           default(""), not null
#  error_message        :string
#  filename             :string
#  import_type          :integer          default("manual"), not null
#  rows_duplicated      :integer          default(0), not null
#  rows_failed          :integer          default(0), not null
#  rows_ok              :integer          default(0), not null
#  rows_total           :integer          default(0), not null
#  status               :integer          default("processing"), not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  account_id           :bigint           not null
#  created_by_id        :bigint
#  jabvox_affiliate_id  :bigint           not null
#
# Indexes
#
#  index_jabvox_affiliate_imports_on_account_id             (account_id)
#  index_jabvox_affiliate_imports_on_affiliate_and_created  (jabvox_affiliate_id,created_at)
#  index_jabvox_affiliate_imports_on_created_by_id          (created_by_id)
#  index_jabvox_affiliate_imports_on_jabvox_affiliate_id    (jabvox_affiliate_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (jabvox_affiliate_id => jabvox_affiliates.id)
#
#  id                  :bigint  not null, primary key
#  account_id          :bigint  not null
#  jabvox_affiliate_id :bigint  not null
#  filename            :string
#  rows_total          :integer default(0), not null
#  rows_ok             :integer default(0), not null
#  rows_failed         :integer default(0), not null
#  import_type         :integer default(0), not null  (0=manual, 1=csv)
#  created_at          :datetime not null
#  updated_at          :datetime not null

class JabvoxAffiliateImport < ApplicationRecord
  self.table_name = 'jabvox_affiliate_imports'

  enum :import_type, { manual: 0, csv: 1 }
  # Una carga masiva se procesa en segundo plano: nace 'processing' y el portal
  # consulta su avance. El alta manual nace ya 'completed'.
  enum :status, { processing: 0, completed: 1, failed: 2 }, prefix: true

  belongs_to :account
  belongs_to :jabvox_affiliate

  # El CSV original, para que el job lo lea fuera del request.
  has_one_attached :source_file

  scope :ordered, -> { order(created_at: :desc) }

  # Filas que ya se resolvieron (montadas + duplicadas + fallidas). Permite
  # mostrar el avance mientras el archivo se procesa.
  def rows_processed
    rows_ok + rows_duplicated + rows_failed
  end

  def progress_percent
    return 100 if status_completed? || rows_total.zero?

    [(rows_processed * 100 / rows_total), 100].min
  end
end
