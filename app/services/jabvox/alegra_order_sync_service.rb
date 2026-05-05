module Jabvox
  class AlegraOrderSyncService
    BASE_URL = 'https://api.alegra.com/api/v1'

    def initialize(account:, order:)
      @account = account
      @order   = order
      @config  = account.jabvox_integration_config
    end

    def sync!
      raise 'No Alegra integration configured' unless @config&.integration_email_jabvox.present?

      payload = build_payload
      endpoint = @order.doc_type == 'SALE' ? 'invoices' : 'quotes'
      response = client.post(endpoint, payload)
      raise "Alegra error (#{response.status}): #{parse_error(response.body)}" unless response.success?

      result = response.body
      @order.update_columns(
        alegra_id: result['id'],
        alegra_number: result['number']&.to_s
      )
      result
    end

    private

    def build_payload
      payload = {
        'date'  => Date.today.iso8601,
        'items' => build_items,
      }
      payload['observations'] = @order.notes if @order.notes.present?
      payload
    end

    def build_items
      @order.jabvox_order_items.map do |item|
        entry = {
          'quantity' => item.quantity.to_f,
          'price'    => item.unit_price.to_f,
          'discount' => item.discount_pct.to_f,
        }
        if item.jabvox_product&.integration_item_id_jabvox.present?
          entry['id'] = item.jabvox_product.integration_item_id_jabvox
        else
          entry['name'] = item.name_snapshot
        end
        entry
      end
    end

    def parse_error(body)
      body.is_a?(Hash) ? (body['message'] || body['error'] || body.to_s) : body.to_s
    end

    def client
      @client ||= Faraday.new(url: BASE_URL) do |f|
        f.request :authorization, :basic, @config.integration_email_jabvox, @config.integration_token_jabvox
        f.request :json
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end
  end
end
