module Jabvox
  class AlegraImportService
    BASE_URL = 'https://api.alegra.com/api/v1'
    BATCH_SIZE = 30
    MAX_ITEMS = 500

    def initialize(account:, config:)
      @account = account
      @config = config
    end

    def import!
      items = fetch_all_items
      default_currency = find_or_create_default_currency
      create_tax_rates_from_items(items)
      results = { created: 0, updated: 0, errors: [] }

      items.each { |item| import_item(item, default_currency, results) }

      results
    end

    private

    def fetch_all_items
      all = []
      start = 0

      loop do
        response = client.get('items', { fields: 'id,name,type,description,price,tax,category,unit', limit: BATCH_SIZE, start: start })
        raise "Error de Alegra (#{response.status}): #{parse_error(response.body)}" unless response.success?

        batch = response.body
        break if batch.blank? || !batch.is_a?(Array)

        all.concat(batch)
        break if batch.size < BATCH_SIZE || all.size >= MAX_ITEMS

        start += BATCH_SIZE
      end

      all
    end

    def import_item(item, currency, results)
      name = item['name']&.strip
      return if name.blank?

      price  = item.dig('price', 0, 'price').to_f
      tax    = item.dig('tax', 0, 'percentage').to_f
      type   = item_type_value(item['type'])

      item_type = find_or_create_item_type(item['type'])
      unit      = find_or_create_unit(item['unit'])

      product = @account.jabvox_products.find_or_initialize_by(integration_item_id_jabvox: item['id'].to_i)
      product.assign_attributes(
        name_jabvox:              name,
        description_jabvox:       item['description'].presence,
        price_jabvox:             price,
        tax_percentage_jabvox:    tax,
        product_type_jabvox:      type,
        jabvox_item_type:         item_type,
        jabvox_unit_of_measure:   unit,
        jabvox_currency:          currency,
        active_jabvox:            true
      )

      if product.new_record?
        product.save!
        results[:created] += 1
      else
        product.save! if product.changed?
        results[:updated] += 1
      end
    rescue StandardError => e
      results[:errors] << "#{item['name']}: #{e.message}"
    end

    def find_or_create_item_type(type_val)
      type_str = type_val.is_a?(Hash) ? type_val['name'] : type_val.to_s
      name = TYPE_NAMES[type_str.strip.downcase] || type_str.strip.capitalize
      return nil if name.blank?

      @account.jabvox_item_types.find_or_create_by!(name_jabvox: name)
    rescue StandardError
      nil
    end

    def find_or_create_unit(unit_data)
      code = unit_data.is_a?(Hash) ? (unit_data['code'] || unit_data['id'].to_s) : unit_data.to_s
      code = code.strip.downcase
      return nil if code.blank?

      name = UNIT_NAMES[code] || (unit_data.is_a?(Hash) ? unit_data['name'] : nil) || code
      @account.jabvox_units_of_measure.find_or_create_by!(abbreviation_jabvox: code) do |u|
        u.name_jabvox = name
      end
    rescue StandardError
      nil
    end

    def create_tax_rates_from_items(items)
      tax_entries = items.flat_map { |i| Array(i['tax']) }.compact
      tax_entries.each do |tax|
        pct  = tax['percentage'].to_f
        name = tax['name'].presence || "IVA #{pct.to_i}%"
        next if name.blank?

        @account.jabvox_tax_rates.find_or_create_by!(name_jabvox: name.strip) do |r|
          r.percentage_jabvox = pct
        end
      rescue StandardError
        nil
      end
    end

    def find_or_create_default_currency
      @account.jabvox_currencies.first ||
        @account.jabvox_currencies.create!(symbol_jabvox: 'COP', name_jabvox: 'Peso Colombiano')
    rescue StandardError
      nil
    end

    def item_type_value(alegra_type)
      alegra_type&.downcase == 'service' ? 'service' : 'product'
    end

    def parse_error(body)
      body.is_a?(Hash) ? (body['message'] || body['error'] || body.to_s) : body.to_s
    end

    def client
      @client ||= Faraday.new(url: BASE_URL) do |f|
        f.request :authorization, :basic, @config.integration_email_jabvox, @config.integration_token_jabvox
        f.response :json
        f.adapter Faraday.default_adapter
      end
    end

    TYPE_NAMES = {
      'product'  => 'Producto',
      'producto' => 'Producto',
      'service'  => 'Servicio',
      'servicio' => 'Servicio',
      'kit'      => 'Kit',
      'bundle'   => 'Paquete',
      'combo'    => 'Combo',
    }.freeze

    UNIT_NAMES = {
      'und'      => 'Unidad',
      'unid'     => 'Unidad',
      'unit'     => 'Unidad',
      'un'       => 'Unidad',
      'kg'       => 'Kilogramo',
      'kilo'     => 'Kilogramo',
      'g'        => 'Gramo',
      'gr'       => 'Gramo',
      'lb'       => 'Libra',
      'lt'       => 'Litro',
      'ltr'      => 'Litro',
      'l'        => 'Litro',
      'ml'       => 'Mililitro',
      'mt'       => 'Metro',
      'mts'      => 'Metro',
      'm'        => 'Metro',
      'cm'       => 'Centímetro',
      'hrs'      => 'Hora',
      'hr'       => 'Hora',
      'hora'     => 'Hora',
      'h'        => 'Hora',
      'min'      => 'Minuto',
      'dia'      => 'Día',
      'dia(s)'   => 'Día',
      'mes'      => 'Mes',
      'par'      => 'Par',
      'doc'      => 'Docena',
      'caja'     => 'Caja',
      'bolsa'    => 'Bolsa',
      'rollo'    => 'Rollo',
      'paq'      => 'Paquete',
      'paquete'  => 'Paquete',
      'srv'      => 'Servicio',
      'serv'     => 'Servicio',
      'servicio' => 'Servicio',
      'svc'      => 'Servicio',
    }.freeze
  end
end
