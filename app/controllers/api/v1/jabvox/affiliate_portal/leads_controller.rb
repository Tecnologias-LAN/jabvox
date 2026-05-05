# frozen_string_literal: true

class Api::V1::Jabvox::AffiliatePortal::LeadsController < Api::V1::Jabvox::AffiliatePortal::BaseController
  PER_PAGE = 25

  def index
    page = (params[:page] || 1).to_i
    leads = @current_account.jabvox_leads
                            .where(jabvox_affiliate_id: @current_affiliate.id)
                            .includes(:contact)
                            .order(lead_number: :asc)
                            .page(page).per(PER_PAGE)

    contact_ids = leads.map(&:contact_id)
    mgmt_data = contact_ids.any? ? fetch_management_data(contact_ids) : {}
    orders_data = contact_ids.any? ? fetch_orders_data(contact_ids) : {}

    render json: {
      data: leads.map { |lead| serialize_lead(lead, mgmt_data, orders_data) },
      meta: {
        total: leads.total_count,
        current_page: leads.current_page,
        total_pages: leads.total_pages
      }
    }
  end

  def history
    page = (params[:page] || 1).to_i
    imports = @current_account.jabvox_affiliate_imports
                              .where(jabvox_affiliate_id: @current_affiliate.id)
                              .ordered
                              .page(page).per(PER_PAGE)

    render json: {
      data: imports.map do |imp|
        {
          id: imp.id,
          filename: imp.filename,
          import_type: imp.import_type,
          rows_total: imp.rows_total,
          rows_ok: imp.rows_ok,
          rows_failed: imp.rows_failed,
          created_at: imp.created_at
        }
      end,
      meta: {
        total: imports.total_count,
        current_page: imports.current_page,
        total_pages: imports.total_pages
      }
    }
  end

  private

  def serialize_lead(lead, mgmt_data, orders_data)
    c = lead.contact
    mgmt = mgmt_data[c.id] || {}
    orders = orders_data[c.id] || {}
    {
      id: lead.id,
      lead_number: lead.lead_number,
      name: c.name,
      email: c.email,
      phone_number: c.phone_number,
      country: c.additional_attributes&.dig('country'),
      last_management_state: mgmt[:last_management_state],
      last_management_at: mgmt[:last_management_at],
      orders_count: orders[:count] || 0,
      orders_total: orders[:total] || '0.00',
      created_at: lead.created_at
    }
  end

  # rubocop:disable Metrics/MethodLength
  def fetch_management_data(contact_ids)
    account_id = @current_account.id.to_i
    safe_ids = contact_ids.map(&:to_i)
    sql = <<~SQL.squish
      SELECT DISTINCT ON (c.contact_id) c.contact_id,
        (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' AS last_management_state,
        m.created_at AS last_management_at
      FROM conversations c
      JOIN messages m ON m.conversation_id = c.id
      WHERE c.account_id = #{account_id}
        AND c.contact_id IN (#{safe_ids.join(', ')})
        AND m.private = true
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' IS NOT NULL
        AND (m.content_attributes #>> '{}')::json->>'jabvox_management_state_name' <> ''
      ORDER BY c.contact_id, m.created_at DESC
    SQL
    ApplicationRecord.connection.execute(sql).each_with_object({}) do |r, h|
      h[r['contact_id'].to_i] = {
        last_management_state: r['last_management_state'],
        last_management_at: r['last_management_at']
      }
    end
  end
  # rubocop:enable Metrics/MethodLength

  def fetch_orders_data(contact_ids)
    safe_ids = contact_ids.map(&:to_i)
    JabvoxOrder
      .where(account_id: @current_account.id, contact_id: safe_ids)
      .group(:contact_id)
      .pluck(:contact_id, Arel.sql('COUNT(*), SUM(total)'))
      .each_with_object({}) do |(cid, count, total), h|
        h[cid] = { count: count, total: total.to_s }
      end
  end
end
