json.array! @states do |s|
  json.partial! 'state', state: s
end
