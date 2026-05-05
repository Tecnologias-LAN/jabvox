# frozen_string_literal: true

# == Schema Information
#
# Table name: jabvox_affiliate_imports
#
#  id                  :bigint           not null, primary key
#  filename            :string
#  import_type         :integer          default("manual"), not null
#  rows_failed         :integer          default(0), not null
#  rows_ok             :integer          default(0), not null
#  rows_total          :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  jabvox_affiliate_id :bigint           not null
#
# Indexes
#
#  index_jabvox_affiliate_imports_on_account_id           (account_id)
#  index_jabvox_affiliate_imports_on_jabvox_affiliate_id  (jabvox_affiliate_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
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

  belongs_to :account
  belongs_to :jabvox_affiliate

  scope :ordered, -> { order(created_at: :desc) }
end
