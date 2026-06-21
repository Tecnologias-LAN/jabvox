# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Jabvox is a customer-support platform (Rails + Vue) built on a heavily customized open-source core, rebranded and extended into an independent product. It keeps the upstream layered core but adds a large amount of fork-specific functionality (telephony/dialer, kanban funnels, affiliates, products, AI chat, SMS, billing/saldo). ~61 of ~111 models are Jabvox-specific (`app/models/jabvox_*.rb` and `app/models/concerns/jabvox/`).

Branding context lives in the user's memory and `config/installation_config.yml`. Brand spelling is **Jabvox / jabvox / JABVOX**.

## Build / Test / Lint

- **Setup**: `bundle install && pnpm install`
- **Ruby version**: managed via `rbenv`; install the version in `.ruby-version`. **Before any `bundle`/`rspec`/`rake`/`rubocop` command, run `eval "$(rbenv init -)"`** so the correct Ruby/Bundler is used. Always prefer `bundle exec`.
- **Run dev**: `pnpm dev` or `overmind start -f ./Procfile.dev` (starts `backend` Rails, `worker` Sidekiq, `vite`, and `ami_listener` for telephony — see Architecture).
- **Lint JS/Vue**: `pnpm eslint` / `pnpm eslint:fix`
- **Lint Ruby**: `bundle exec rubocop -a`
- **Test JS**: `pnpm test` / `pnpm test:watch`
- **Test Ruby**: `bundle exec rspec spec/path/to/file_spec.rb`
- **Single Ruby test**: `bundle exec rspec spec/path/to/file_spec.rb:LINE_NUMBER`
- **Seed minimal data**: `bundle exec rails db:seed`
- **Seed bulk search data**: `bundle exec rails search:setup_test_data`
- **Seed rich sample account**: `bundle exec rails runner "Internal::SeedAccountJob.perform_now(Account.find(<id>))"` (or Super Admin → Accounts → Seed, or `Seeders::AccountSeeder.new(account: Account.find(<id>)).perform!`)

## Architecture (big picture)

**Backend (Rails)** follows the upstream layered, event-driven conventions — understand these before adding logic:
- `app/services/` — business logic (the primary place for new behavior). Jabvox features under `app/services/jabvox/` (dialer, kanban automation, Alegra sync, saldo, calendar reminders).
- `app/builders/` — object construction (e.g. message builders per channel).
- `app/finders/` — query objects. `app/actions/` — small composable operations. `app/drops/` — Liquid drops for email/automation templating.
- `app/dispatchers/` + `app/listeners/` — **event bus**. Code emits events through `Dispatcher` (sync/async); listeners (`base_listener.rb` subclasses) react. Use this instead of stuffing side-effects into models/controllers.
- `app/jobs/` — Sidekiq background work. Scheduled jobs are declared in `config/schedule.yml` (sidekiq-cron).
- Real-time via ActionCable: `app/channels/room_channel.rb` + `ActionCableListener`.
- Mailers in `app/mailers/`; templates in `app/views/mailers/` (HTML `.erb` and Liquid `.liquid`, the latter overridable per-account via `EmailTemplate`).

**Account feature composition**: Jabvox capabilities are mixed into core models via concerns in `app/models/concerns/jabvox/` (e.g. `account_voip_feature`, `account_products_feature`, `account_ai_chat_feature`). When adding an account-level feature, follow this concern pattern rather than editing `Account` inline.

**Telephony**: `Jabvox::AmiListenerRunner` (started as the `ami_listener` process in `Procfile.dev`) connects to Asterisk AMI; the dialer lives in `app/services/jabvox/dialer_service.rb` and related `jabvox_dialer_*` models.

**Frontend** is multiple independent Vue 3 SPAs, each with its own Vite entrypoint in `app/javascript/entrypoints/` and source tree under `app/javascript/`:
- `dashboard/` — main agent app (the bulk of the UI)
- `widget/` — embeddable live-chat widget (visitor-facing)
- `sdk/` — the JS SDK that boots the widget on customer sites (`window.$jabvox` API)
- `portal/` — public help center · `survey/` — CSAT surveys · `v3/` — newer public flows · `superadmin_pages/` — super admin · `affiliate_portal/` — Jabvox affiliates
- `shared/` and `design-system/` are cross-app.

State: dashboard uses Vuex (legacy, being migrated) and Pinia. Prefer `components-next/` for new components (the older component tree is being deprecated).

## Enterprise overlay

An `enterprise/` tree (~355 files, ~67 `prepend_mod_with`/`include_mod_with` call sites) extends/overrides OSS code. For any change to core logic or public APIs:
- Search both trees first: `rg -n "FooService|ControllerName|ModelName" app enterprise`.
- Extend OSS behavior from Enterprise via `prepend_mod_with`/`include_mod_with` (especially policies, controllers, services) — do **not** edit OSS files for Enterprise-only behavior. Enterprise-exclusive features go directly under `enterprise/`.
- Keep request/response contracts identical across OSS and Enterprise; update both route/controller sets together. Mirror renames/moves into `enterprise/` to prevent drift. Enterprise specs go under `spec/enterprise/`.

## Rebranding — DO NOT RENAME (breaks app / integrations / production)

The internal `Chatwoot*` identifiers have been renamed to Jabvox: Ruby modules/classes (`module Jabvox`, `JabvoxApp`, `JabvoxHub`, `JabvoxCaptcha`, `JabvoxExceptionTracker`, `JabvoxMarkdownRenderer`, `lib/jabvox_*.rb`), the JS SDK contract (`window.$jabvox`, `jabvoxSDK`, `jabvoxSettings`, `jabvoxWebChannel`, `jabvoxConfig`, events `jabvox:ready`/`JABVOX_*`, postMessage prefix `jabvox-widget:`), and the deploy identity templates (`deployment/jabvox-*`, user `jabvox`, `/home/jabvox`). The brand text is centralized (`config/installation_config.yml` → `INSTALLATION_NAME`/`BRAND_NAME` — actual values live in the `installation_configs` DB table — plus `shared/composables/useBranding.js` whose `replaceInstallationName` still swaps any legacy "Chatwoot" string → installation name at runtime via `/Chatwoot/g`; keep that regex so any stray upstream string is normalized).

**Still NOT renamed (would break things), all invisible to end users:**
- npm deps `@chatwoot/*` (published third-party packages); the `Gemfile.lock` `branch: chatwoot` refs (third-party gem branches on GitHub).
- env/redis/config keys whose names are the data contract: `CHATWOOT_*` installation-config keys (`CHATWOOT_INBOX_TOKEN`, `CHATWOOT_SUPPORT_*`, etc.), Redis keys (`CHATWOOT_INSTALLATION_*`, `LATEST_CHATWOOT_VERSION`), feature-flag names (`chatwoot_internal`, `chatwoot_v4`), API field `latest_chatwoot_version` + i18n var `{latestChatwootVersion}`.
- The physical DB name in production (`chatwoot_production`): the `database.yml` defaults are `jabvox_*` and dev/test DBs were renamed to `jabvox_dev`/`jabvox_test`, but production must be migrated via `RUNBOOK_migracion_db_jabvox.md` before changing `POSTGRES_DATABASE`.
- Third-party URLs in comments / installer scripts (`github.com/chatwoot`, `hub.2.chatwoot.com`).

For new user-facing strings that should adapt to the install name, apply `replaceInstallationName` rather than hardcoding a brand.

**Telemetry is intentionally disabled**: `lib/jabvox_hub.rb` `sync_with_hub`/`register_instance`/`emit_event` return nil (no outbound data). Mobile push (`send_push`) is kept but routes through `JabvoxHub.base_url`, which reads `JABVOX_HUB_URL` (point it at your own relay). Do not re-introduce hub calls.

## Conventions

- **Ruby**: RuboCop, 150-char lines. Compact `module/class` definitions (no nested style). Custom exceptions in `lib/custom_exceptions/`. Strong params. Models validate presence/uniqueness and add indexes.
- **Vue/JS**: ESLint (Airbnb base + Vue 3). Composition API with `<script setup>` at top. PascalCase components, camelCase events, PropTypes.
- **Styling**: Tailwind utility classes only — no custom CSS, no scoped CSS, no inline styles. Colors from `tailwind.config.js`.
- **i18n**: no bare strings in templates. **Only edit the English files** (`en.yml` backend, `en.json` frontend); other locales are community-managed.
- **Specs**: don't write specs unless asked. Prefer `with_modified_env` over stubbing `ENV`. In parallel/reloading specs, compare `error.class.name` over constant equality.

## General approach

- MVP focus: least change, happy-path first; add guards/fallbacks only where production has proven them necessary.
- Prefer minimal readable code over abstractions. Remove dead code. One implementation per piece of logic — no parallel versions/backups. Iterate after confirmation.

## Worktree workflow (Codex)

Use a separate git worktree + branch per task. Keep local setup under `.codex/`; use `Procfile.worktree`. `.codex/environments/environment.toml` generates per-worktree DB/port/Redis-index values to avoid collisions, each with its own Overmind socket/title.

## Commits & PRs

- Conventional Commits: `type(scope): subject` (e.g. `feat(auth): add user authentication`). Don't reference Claude in commit messages.
- PR description: lead with a short user-facing paragraph; add a `Closes` section (GitHub/Linear links); `How to test` for features, `How to reproduce` for bugfixes; optional `What changed`. Do not add a section listing the specs/commands you ran.
