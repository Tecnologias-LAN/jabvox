json.payload do
  json.array! @stages do |stage|
    json.partial! 'stage', stage: stage
  end
end
