json.data do
  json.array! @categories do |category|
    json.partial! 'api/v1/accounts/jabvox/tickets/categories/category', category: category
  end
end
