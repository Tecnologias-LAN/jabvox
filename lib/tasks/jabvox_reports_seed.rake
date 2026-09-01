# frozen_string_literal: true

# Seeds realistic report data for the analytics reports panel so the summary,
# drill-down, rollups and p95 targets can be measured locally.
#
#   bundle exec rails "jabvox:reports:seed[174,90,200]"
#     account_id=174, days=90, ~200 events/day/metric
#
#   REPORTS_SEED_MESSAGES=1000000 bundle exec rails jabvox:reports:seed_bulk[174]
#     bulk 1M messages for load testing (fast, minimal associations)
namespace :jabvox do
  namespace :reports do
    desc 'Seed realistic multi-metric report data for an account'
    task :seed, %i[account_id days per_day] => :environment do |_t, args|
      account = Account.find(args[:account_id] || 174)
      days = (args[:days] || 60).to_i
      per_day = (args[:per_day] || 50).to_i
      Jabvox::Reports::SeedBuilder.new(account: account, days: days, per_day: per_day).run
    end

    desc 'Bulk-seed N messages for load testing (fast insert_all)'
    task :seed_bulk, %i[account_id] => :environment do |_t, args|
      account = Account.find(args[:account_id] || 174)
      total = ENV.fetch('REPORTS_SEED_MESSAGES', '1000000').to_i
      Jabvox::Reports::SeedBuilder.new(account: account, days: 365, per_day: 0).bulk_messages!(total)
    end
  end
end
