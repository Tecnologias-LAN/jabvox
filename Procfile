release: POSTGRES_STATEMENT_TIMEOUT=600s bundle exec rails db:jabvox_prepare && echo $SOURCE_VERSION > .git_sha
web: bundle exec rails ip_lookup:setup && bin/rails server -p $PORT -e $RAILS_ENV
worker: bundle exec rails ip_lookup:setup && bundle exec sidekiq -C config/sidekiq.yml
flows: bundle exec sidekiq -C config/sidekiq_flows.yml
voice_broadcast: bundle exec sidekiq -C config/sidekiq_voice_broadcast.yml
