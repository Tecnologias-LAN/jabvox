json.payload do
  json.array! @funnels do |funnel|
    json.partial! 'funnel', funnel: funnel
  end
end
