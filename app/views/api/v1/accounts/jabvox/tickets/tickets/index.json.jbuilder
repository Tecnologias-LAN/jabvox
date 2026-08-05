json.data do
  json.array! @tickets do |ticket|
    json.partial! 'api/v1/accounts/jabvox/tickets/tickets/ticket', ticket: ticket, detailed: false
  end
end

json.meta do
  json.total @total
  json.current_page @tickets.current_page
  json.total_pages @tickets.total_pages
end
