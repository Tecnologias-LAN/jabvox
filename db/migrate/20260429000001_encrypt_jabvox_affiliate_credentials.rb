# frozen_string_literal: true

class EncryptJabvoxAffiliateCredentials < ActiveRecord::Migration[7.1]
  def up
    return unless ActiveRecord::Encryption.config.primary_key.present?

    JabvoxAffiliate.find_each do |affiliate|
      affiliate.encrypt
    rescue StandardError
      # already encrypted or encryption not configured
    end
  end

  def down
    # irreversible — encrypted data stays encrypted
  end
end
