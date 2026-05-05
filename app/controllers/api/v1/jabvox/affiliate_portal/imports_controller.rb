# frozen_string_literal: true

class Api::V1::Jabvox::AffiliatePortal::ImportsController < Api::V1::Jabvox::AffiliatePortal::BaseController
  MAX_ROWS = 5_000

  # POST /api/v1/jabvox/affiliate_portal/imports
  # Param: file (CSV), columns: name, email, phone, country
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def create
    return render json: { error: 'file_missing' }, status: :unprocessable_entity if params[:file].blank?

    rows = parse_csv(params[:file])
    return render json: { error: 'file_empty' }, status: :unprocessable_entity if rows.empty?
    return render json: { error: 'too_many_rows', max: MAX_ROWS }, status: :unprocessable_entity if rows.size > MAX_ROWS

    ok = 0
    failed = 0

    rows.each do |row|
      name = row['name'].to_s.strip
      next if name.blank?

      ActiveRecord::Base.transaction do
        contact = @current_account.contacts.create!(
          name: name,
          email: row['email'].to_s.strip.presence,
          phone_number: row['phone'].to_s.strip.presence,
          additional_attributes: { country: row['country'].to_s.strip.presence }.compact
        )
        lead = JabvoxLead.find_or_initialize_by(account: @current_account, contact: contact)
        lead.jabvox_affiliate = @current_affiliate
        lead.save!
        ok += 1
      end
    rescue StandardError
      failed += 1
    end

    import = JabvoxAffiliateImport.create!(
      account: @current_account,
      jabvox_affiliate: @current_affiliate,
      import_type: :csv,
      filename: params[:file].original_filename,
      rows_total: rows.size,
      rows_ok: ok,
      rows_failed: failed
    )

    render json: serialize_import(import), status: :created
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  private

  def parse_csv(file)
    require 'csv'
    content = file.read.force_encoding('UTF-8')
    csv = CSV.parse(content, headers: true, header_converters: :downcase, skip_blanks: true)
    csv.map(&:to_h)
  rescue CSV::MalformedCSVError
    []
  end

  def serialize_import(import)
    {
      id: import.id,
      filename: import.filename,
      rows_total: import.rows_total,
      rows_ok: import.rows_ok,
      rows_failed: import.rows_failed,
      created_at: import.created_at
    }
  end
end
