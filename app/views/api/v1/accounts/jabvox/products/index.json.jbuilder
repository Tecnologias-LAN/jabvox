json.array! @products do |product|
  json.id product.id
  json.name_jabvox product.name_jabvox
  json.description_jabvox product.description_jabvox
  json.price_jabvox product.price_jabvox
  json.base_price_jabvox product.base_price_jabvox
  json.tax_percentage_jabvox product.tax_percentage_jabvox
  json.total_price_jabvox product.total_price_jabvox
  json.active_jabvox product.active_jabvox
  json.product_type_jabvox product.product_type_jabvox
  json.integration_item_id_jabvox product.integration_item_id_jabvox
  json.jabvox_currency_id product.jabvox_currency_id
  json.jabvox_item_type_id product.jabvox_item_type_id
  json.jabvox_unit_of_measure_id product.jabvox_unit_of_measure_id
  json.currency product.jabvox_currency, :id, :symbol_jabvox, :name_jabvox if product.jabvox_currency
  json.item_type product.jabvox_item_type, :id, :name_jabvox if product.jabvox_item_type
  json.unit_of_measure product.jabvox_unit_of_measure, :id, :name_jabvox, :abbreviation_jabvox if product.jabvox_unit_of_measure
  json.created_at product.created_at
  json.updated_at product.updated_at
end
