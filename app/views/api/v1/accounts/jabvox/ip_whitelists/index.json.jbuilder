json.array! @entries do |entry|
  json.partial! 'api/v1/accounts/jabvox/ip_whitelists/entry', entry: entry
end
