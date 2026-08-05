json.data do
  json.array! @comments do |comment|
    json.partial! 'api/v1/accounts/jabvox/tickets/comments/comment', comment: comment
  end
end
