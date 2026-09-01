Rails.application.routes.draw do
  # AUTH STARTS
  mount_devise_token_auth_for 'User', at: 'auth', controllers: {
    confirmations: 'devise_overrides/confirmations',
    passwords: 'devise_overrides/passwords',
    sessions: 'devise_overrides/sessions',
    token_validations: 'devise_overrides/token_validations',
    omniauth_callbacks: 'devise_overrides/omniauth_callbacks'
  }, via: [:get, :post]

  post 'resend_confirmation', to: 'auth/resend_confirmations#create'

  ## renders the frontend paths only if its not an api only server
  if ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false))
    root to: 'api#index'
  else
    root to: 'dashboard#index'

    get '/app', to: 'dashboard#index'
    get '/app/*params', to: 'dashboard#index'
    get '/:portal_account_id/affiliate-portal/login/:affiliate_slug', to: 'affiliate_portal#index'
    get '/:portal_account_id/affiliate-portal/:affiliate_slug', to: 'affiliate_portal#index'
    get '/:portal_account_id/affiliate-portal/:affiliate_slug/*rest', to: 'affiliate_portal#index'
    get '/app/accounts/:account_id/settings/inboxes/new/twitter', to: 'dashboard#index', as: 'app_new_twitter_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/microsoft', to: 'dashboard#index', as: 'app_new_microsoft_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/instagram', to: 'dashboard#index', as: 'app_new_instagram_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/tiktok', to: 'dashboard#index', as: 'app_new_tiktok_inbox'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_twitter_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_email_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_instagram_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/new/:inbox_id/agents', to: 'dashboard#index', as: 'app_tiktok_inbox_agents'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_instagram_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_tiktok_inbox_settings'
    get '/app/accounts/:account_id/settings/inboxes/:inbox_id', to: 'dashboard#index', as: 'app_email_inbox_settings'
    get '/app/accounts/:account_id/onboarding/inbox-setup', to: 'dashboard#index', as: 'app_onboarding_inbox_setup'

    resource :widget, only: [:show]
    get '/f/:account_id/:slug', to: 'jabvox_forms#show', as: 'jabvox_public_form'
    post '/f/:account_id/:slug', to: 'jabvox_forms#submit'
    get '/.well-known/acme-challenge/:token', to: 'jabvox/acme_challenges#show'
    namespace :survey do
      resources :responses, only: [:show]
    end
    resource :slack_uploads, only: [:show]
  end

  get '/health', to: 'health#show'
  get '/api', to: 'api#index'
  namespace :api, defaults: { format: 'json' } do
    namespace :v1 do
      # ----------------------------------
      # start of account scoped api routes
      resources :accounts, only: [:create, :show, :update] do
        member do
          post :update_active_at
          get :cache_keys
        end

        scope module: :accounts do
          namespace :actions do
            resource :contact_merge, only: [:create]
          end
          resource :bulk_actions, only: [:create]
          resource :onboarding, only: [:update] do
            get :help_center_generation
          end
          resources :agents, only: [:index, :create, :update, :destroy] do
            post :bulk_create, on: :collection
          end
          namespace :captain do
            resource :preferences, only: [:show, :update]
            resources :assistants do
              member do
                post :playground
                get :metrics
                get :faq_stats
                get :summary
                get :drilldown
              end
              collection do
                get :tools
              end
              resources :inboxes, only: [:index, :create, :destroy], param: :inbox_id
              resources :scenarios
            end
            resources :agent_sessions, only: [:show]
            resources :assistant_responses
            resources :faq_suggestions, only: [:index, :show, :update] do
              post :approve, on: :member
              post :dismiss, on: :member
            end
            resources :message_reports, only: [:create]
            resources :bulk_actions, only: [:create]
            resources :copilot_threads, only: [:index, :create] do
              resources :copilot_messages, only: [:index, :create]
            end
            resources :custom_tools do
              post :test, on: :collection
            end
            resources :documents, only: [:index, :show, :create, :destroy] do
              post :sync, on: :member
            end
            resource :tasks, only: [], controller: 'tasks' do
              post :rewrite
              post :summarize
              post :reply_suggestion
              post :label_suggestion
              post :follow_up
            end
          end
          resource :saml_settings, only: [:show, :create, :update, :destroy]
          resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
            delete :avatar, on: :member
            post :reset_access_token, on: :member
            post :reset_secret, on: :member
          end
          resources :contact_inboxes, only: [] do
            collection do
              post :filter
            end
          end
          resources :assignable_agents, only: [:index]
          resource :audit_logs, only: [:show]
          resources :callbacks, only: [] do
            collection do
              post :register_facebook_page
              get :register_facebook_page
              post :facebook_pages
              post :reauthorize_page
            end
          end
          resources :canned_responses, only: [:index, :create, :update, :destroy]
          resources :automation_rules, only: [:index, :create, :show, :update, :destroy] do
            post :clone
          end
          resources :macros, only: [:index, :create, :show, :update, :destroy] do
            post :execute, on: :member
          end
          resources :sla_policies, only: [:index, :create, :show, :update, :destroy]
          resources :custom_roles, only: [:index, :create, :show, :update, :destroy]
          resources :agent_capacity_policies, only: [:index, :create, :show, :update, :destroy] do
            scope module: :agent_capacity_policies do
              resources :users, only: [:index, :create, :destroy]
              resources :inbox_limits, only: [:create, :update, :destroy]
            end
          end
          resources :campaigns, only: [:index, :create, :show, :update, :destroy]
          resources :dashboard_apps, only: [:index, :show, :create, :update, :destroy]
          namespace :channels do
            resource :twilio_channel, only: [:create]
          end
          resources :conversations, only: [:index, :create, :show, :update, :destroy] do
            collection do
              get :meta
              get :search
              get :unread_counts, to: 'conversations/unread_counts#index'
              post :filter
            end
            scope module: :conversations do
              resources :messages, only: [:index, :create, :destroy, :update] do
                member do
                  post :translate
                  post :retry
                end
              end
              resources :assignments, only: [:create]
              resources :labels, only: [:create, :index]
              resource :participants, only: [:show, :create, :update, :destroy]
              resource :direct_uploads, only: [:create]
              resource :draft_messages, only: [:show, :update, :destroy]
            end
            member do
              post :mute
              post :unmute
              post :transcript
              post :toggle_status
              post :toggle_priority
              post :toggle_typing_status
              post :update_last_seen
              post :unread
              post :custom_attributes
              get :attachments
              get :inbox_assistant
              get :reporting_events if JabvoxApp.enterprise?
            end
          end

          resources :search, only: [:index] do
            collection do
              get :conversations
              get :messages
              get :contacts
              get :articles
            end
          end

          resources :companies, only: [:index, :show, :create, :update, :destroy] do
            collection do
              get :search
            end
            member do
              post :destroy_custom_attributes
              delete :avatar
            end
            scope module: :companies do
              resources :contacts, only: [:index, :create, :destroy] do
                collection do
                  get :search
                end
              end
              resources :conversations, only: [:index]
              resources :notes, only: [:index]
            end
          end
          resources :contacts, only: [:index, :show, :update, :create, :destroy] do
            collection do
              get :active
              get :search
              post :filter
              post :import
              post :export
              get :sample_import
            end
            member do
              get :contactable_inboxes
              post :destroy_custom_attributes
              delete :avatar
            end
            scope module: :contacts do
              resources :conversations, only: [:index]
              resources :contact_inboxes, only: [:create]
              resources :labels, only: [:create, :index]
              resources :notes
              get :attachments, to: 'attachments#index'
              post :call, on: :member, to: 'calls#create' if JabvoxApp.enterprise?
            end
          end
          resources :data_imports, only: [:index, :show, :create] do
            collection do
              post :validate_source
            end
            member do
              post :start
              post :retry, action: :retry_import
              post :abandon
              get :error_logs
              get :skip_logs
            end
          end
          resources :csat_survey_responses, only: [:index] do
            collection do
              get :metrics
              get :download
            end
            member do
              patch :update if JabvoxApp.enterprise?
            end
          end
          resources :applied_slas, only: [:index] do
            collection do
              get :metrics
              get :download
            end
          end
          resources :reporting_events, only: [:index] if JabvoxApp.enterprise?

          if JabvoxApp.enterprise?
            resources :calls, only: [:index]
            resources :whatsapp_calls, only: [:show] do
              member do
                post :accept
                post :reject
                post :terminate
                post :upload_recording
              end
              collection do
                post :initiate
              end
            end
          end

          resources :custom_attribute_definitions, only: [:index, :show, :create, :update, :destroy]
          resources :custom_filters, only: [:index, :show, :create, :update, :destroy]
          resource :branded_email_layout, only: [:show, :update]
          resources :inboxes, only: [:index, :show, :create, :update, :destroy] do
            get :assignable_agents, on: :member
            get :campaigns, on: :member
            get :agent_bot, on: :member
            post :set_agent_bot, on: :member
            delete :avatar, on: :member
            post :sync_templates, on: :member
            get :health, on: :member
            post :register_webhook, on: :member
            post :reset_secret, on: :member
            if JabvoxApp.enterprise?
              resource :conference, only: %i[create destroy], controller: 'conference' do
                get :token, on: :member
              end
              post :enable_whatsapp_calling, on: :member
              post :disable_whatsapp_calling, on: :member
              post :set_inbound_calls, on: :member
            end

            resource :csat_template, only: [:show, :create], controller: 'inbox_csat_templates' do
              post :analyze, on: :collection
            end
          end

          resources :inbox_members, only: [:create, :show], param: :inbox_id do
            collection do
              delete :destroy
              patch :update
            end
          end
          resources :labels, only: [:index, :show, :create, :update, :destroy]

          resources :notifications, only: [:index, :update, :destroy] do
            collection do
              post :read_all
              get :unread_count
              post :destroy_all
            end
            member do
              post :snooze
              post :unread
            end
          end
          resource :notification_settings, only: [:show, :update]

          resources :teams do
            resources :team_members, only: [:index, :create] do
              collection do
                delete :destroy
                patch :update
              end
            end
          end

          # Assignment V2 Routes
          resources :assignment_policies do
            resources :inboxes, only: [:index, :create, :destroy], module: :assignment_policies
          end

          resources :inboxes, only: [] do
            resource :assignment_policy, only: [:show, :create, :destroy], module: :inboxes
          end

          namespace :twitter do
            resource :authorization, only: [:create]
          end

          namespace :microsoft do
            resource :authorization, only: [:create]
          end

          namespace :google do
            resource :authorization, only: [:create]
          end

          namespace :instagram do
            resource :authorization, only: [:create]
          end

          namespace :tiktok do
            resource :authorization, only: [:create]
          end

          namespace :notion do
            resource :authorization, only: [:create]
          end

          namespace :whatsapp do
            resource :authorization, only: [:create]
          end

          resources :webhooks, only: [:index, :create, :update, :destroy]
          namespace :integrations do
            resources :apps, only: [:index, :show]
            resources :hooks, only: [:show, :create, :update, :destroy] do
              member do
                post :process_event
              end
            end
            resource :slack, only: [:create, :update, :destroy], controller: 'slack' do
              member do
                get :list_all_channels
              end
            end
            resource :dyte, controller: 'dyte', only: [] do
              collection do
                post :create_a_meeting
                post :add_participant_to_meeting
              end
            end
            resource :shopify, controller: 'shopify', only: [:destroy] do
              collection do
                post :auth
                get :orders
              end
            end
            resource :linear, controller: 'linear', only: [] do
              collection do
                delete :destroy
                get :teams
                get :team_entities
                post :create_issue
                post :link_issue
                post :unlink_issue
                get :search_issue
                get :linked_issues
              end
            end
            resource :notion, controller: 'notion', only: [] do
              collection do
                delete :destroy
              end
            end
          end
          resources :portals do
            member do
              patch :archive
              delete :logo
              post :send_instructions
              get :ssl_status
            end
            resources :categories do
              post :reorder, on: :collection
            end
            namespace :articles do
              resource :bulk_actions, only: [] do
                post :translate
                patch :update_status
                patch :update_category
                delete :delete_articles
              end
            end
            resources :articles do
              post :reorder, on: :collection
            end
          end

          resources :upload, only: [:create]

          namespace :jabvox do
            # Softphone WebRTC: credenciales efímeras + historial de llamadas.
            namespace :softphone do
              resource :credentials, only: [:show], controller: 'credentials'
              resources :call_logs, only: [:index, :create, :update], controller: 'call_logs' do
                post :event, on: :member
              end
              # Heartbeat de presencia: el navegador reporta su estado en vivo
              # (registrado/en llamada/caído) para el panel de estado del super admin.
              resource :presence, only: [:update], controller: 'presence'
            end
            # Cobro/aprovisionamiento: inicia el checkout (token firmado + URL de la web)
            # y expone el estado de pago para el modal de bloqueo del frontend.
            namespace :billing do
              resource :checkout, only: [:create], controller: 'checkouts'
              resource :status, only: [:show], controller: 'status'
              # Historial de pagos de la cuenta (medio, monto, fecha, estado).
              resources :payments, only: [:index], controller: 'payments'
            end
            # Fecha en que se aplicó una etiqueta (para automatizaciones que la retiran
            # tras cierto tiempo). No lo ofrece la API estándar de Chatwoot.
            resources :label_logs, only: [:index]
            # Automatizaciones avanzadas (flujos): editor nativo del dashboard.
            namespace :flows do
              # Los recursos hermanos van ANTES: `resources :flows` cuelga de la
              # raíz del espacio y si no capturaría /nodes, /folders… como ids.
              resources :folders, only: [:index, :create, :update, :destroy]
              resources :variables, only: [:index, :create, :update, :destroy]
              resources :runs, only: [:index, :show] do
                collection { get :stats }
                member { post :resume }
              end
              resources :nodes, only: [:index]
              get 'options/:kind', to: 'options#show'
              # Cuota de flujos de la cuenta (usado/tope), para avisar antes de crear.
              get 'quota', to: 'flows#quota'
              resources :flows, only: [:index, :show, :create, :update, :destroy], path: '/' do
                member do
                  post :duplicate
                  put 'versions', action: :save_version
                  get 'versions', action: :versions
                  get 'versions/:v', action: :version
                  post 'versions/:v/restore', action: :restore_version
                  post :validate
                  post :run
                  post :run_from
                  post :run_node
                  get :runs
                end
              end
            end
            resources :kanban_funnels do
              resources :kanban_stages, only: [:index, :create, :update, :destroy] do
                resources :kanban_stage_automations, only: [:index, :create, :show, :update, :destroy]
              end
              resource :kanban_board, only: [:show], controller: 'kanban_board'
              resource :kanban_conversation_stages, only: [:update], controller: 'kanban_conversation_stages' do
                collection do
                  put :update_lead
                end
              end
            end
            resource :smtp_config, only: [:show, :create, :update, :destroy] do
              post :test, on: :member
            end
            resource :calendar_setting, only: [:show, :update]
            resources :email_templates do
              member do
                post :test_send
                post :send_to_contact
              end
            end
            resource :email, only: [], controller: 'emails' do
              post :send_message, on: :collection
            end
            resources :products do
              collection do
                post :import
              end
            end
            resources :orders do
              member { post :send_to_alegra }
            end
            resources :discounts
            resources :order_status_configs
            resources :management_states do
              collection do
                get :export
                post :import
              end
            end
            resources :app_states, only: [:index, :create, :update, :destroy] do
              collection { patch :set_presence }
            end
            resources :internal_chats, only: [:index, :create] do
              collection do
                get :unread_count
                get :account_users
              end
              member do
                get :messages
                post :send_message
                patch :mark_read
              end
            end
            resources :leads, only: [:index, :show] do
              collection do
                post :sync_contacts
                patch :bulk_assign
                patch :bulk_unassign
                delete :bulk_destroy
                get :matching_lead_ids
                get 'for_contact/:contact_id', action: :for_contact, as: :for_contact
                patch 'for_contact/:contact_id', action: :update_contact_lead, as: :update_contact_lead
              end
              # Multi-row custom tables for a lead. The path id is the TABLE id
              # (a lead can have many rows per table); the specific row is passed
              # as row_id in the body/query for update/destroy.
              get 'custom_table_rows', to: 'custom_table_rows#index'
              post 'custom_table_rows/:id', to: 'custom_table_rows#create'
              patch 'custom_table_rows/:id', to: 'custom_table_rows#update'
              delete 'custom_table_rows/:id', to: 'custom_table_rows#destroy'
              member do
                patch :custom_fields
                patch :update_details
                patch :claim
              end
            end
            resources :lead_campaigns, controller: 'campaigns'
            resources :field_visibilities, only: [:index] do
              collection do
                get :me
                patch :update
              end
            end
            resources :currencies
            resources :item_types
            resources :units_of_measure
            resources :tax_rates
            resource :integration_config, only: [:show, :update, :destroy]
            resources :sales_report_accesses, only: [:index, :update] do
              collection { get :me }
            end
            resource :sales_reports, only: [:show]
            resource :voip_config, only: [:show, :update]
            get :voip_status, to: 'voip_configs#status'
            post :voip_originate, to: 'voip_configs#originate'
            namespace :whatsapp_templates do
              get :inboxes, to: 'inboxes#index'
              post 'inboxes/:inbox_id/sync', to: 'inboxes#sync'
              post :sync_all, to: 'inboxes#sync_all'
              post :sync_all_async, to: 'inboxes#sync_all_async'
              get :metrics, to: 'inboxes#metrics'
              # Templates are managed at Meta; Jabvox can view/create/update/duplicate/sync
              # but NOT delete them (deletion is done from Meta). No :destroy route.
              resources :templates, except: [:destroy] do
                member do
                  post :duplicate
                  post :sync
                  get :history
                  get :versions
                  post :restore_version
                end
              end
            end
            namespace :cdr do
              resource :config, only: [:show, :update], controller: 'configs'
              post 'config/test', to: 'configs#test'
              post 'config/test_ssh', to: 'configs#test_ssh'
              resources :pipelines
              get :my_access, to: 'reports#my_access'
              get :records, to: 'reports#records'
              get :summary, to: 'reports#summary'
              # Sincroniza el CDR del PBX -> tabla local bajo demanda (al abrir la
              # vista), para traer las llamadas nuevas desde la última sincronización.
              post :sync_now, to: 'reports#sync_now'
              # Estado del sincronizador (dashboard de monitoreo, solo admin).
              get :monitor, to: 'reports#monitor'
              post :analyze, to: 'reports#analyze'
              post :typify, to: 'reports#typify'
              post :analyses_batch, to: 'reports#analyses_batch'
              get 'analysis/:uniqueid', to: 'reports#analysis', constraints: { uniqueid: %r{[^/]+} }
              get 'analysis/:uniqueid/recording', to: 'reports#recording', constraints: { uniqueid: %r{[^/]+} }
            end
            resources :typifications, only: [:index, :create, :update, :destroy] do
              collection do
                get :export
                post :import
              end
            end
            namespace :click_to_call do
              resources :calls, only: [:create, :destroy]
              resources :call_logs, only: [:index, :show, :update]
            end
            namespace :audio_analysis do
              resources :storages, only: [:index, :create, :update, :destroy] do
                collection { post :test }
                member do
                  get :objects
                  post :assign
                  get :playback
                end
              end
              resources :pipelines
              resources :jobs, only: [:index, :show, :create] do
                member { get :results }
              end
              get 'reports/daily', to: 'reports#daily'
              get 'reports/filter_options', to: 'reports#filter_options'
              get 'access/my', to: 'reports#my_access'
            end
            resource :saldo_config, only: [:show, :update]
            get :saldo_balance, to: 'saldo_configs#status'
            resources :sms_providers do
              member { get :check_connection }
            end
            resources :sms_campaigns do
              member { post :send_bulk }
              collection do
                get :contacts
                get :lead_count
              end
            end
            resources :sms_messages, only: [:index] do
              collection do
                get :stats
                post :send_to_contact
              end
            end
            resources :ip_whitelists, only: [:index, :create, :update, :destroy]
            resources :dialer_campaigns do
              collection do
                get :lead_count
                get :matching_lead_ids
                get :preview_leads
                get :lead_fields
                get :field_values
              end
              member do
                patch :start
                patch :pause
                patch :stop
                patch :retry_contacts
                patch :redial_lead
                patch :exclude_lead
                get :contacts
                get :call_logs
                get :report
                get :progress
                get :live_monitor
                post :import_contacts
                post :originate
              end
            end
            resources :dialer_call_logs, only: [:index, :create] do
              collection { patch :typify }
              member { patch :typify }
            end
            # Agente virtual / Voice Broadcast saliente (reutiliza la lista de una campaña).
            resources :voice_broadcasts, only: [:index, :show, :create, :update, :destroy] do
              member do
                post :audio
                post :start
                post :pause
                post :resume
                post :stop
                get :live_monitor
                get :report
                get :report_csv
              end
            end
            resources :dialer_states, only: [:index, :create, :update, :destroy]
            resources :dialer_accesses, only: [:index, :update] do
              collection do
                get :me
                post :connect
                delete :connect, action: :disconnect
                patch :state, action: :update_state
                patch :wrapup, action: :set_wrapup
                post :heartbeat
                get :available_agents
                post :request_call
                patch :end_call
              end
            end
            resources :dialer_events, only: [:create]
            resource :user_extension, only: [:show], controller: 'user_extensions'
            resources :user_extensions, only: [:index, :create, :destroy], controller: 'user_extensions'
            resources :ai_chat_models, only: [:index, :create, :update, :destroy] do
              member do
                patch :set_default
                post :test_connection
              end
            end
            resources :ai_chat_configs, only: [] do
              collection do
                get '/', action: :show
                patch '/', action: :update
                get :bucket_objects
                post :save_documents
              end
            end
            resources :ai_chat_messages, only: [:index, :create, :destroy] do
              collection do
                get :my_access
                get :sessions
                post :stream
              end
            end
            # Storages (buckets) — se conservan porque el Response Bot los comparte vía
            # ai_chat_config. Documentos del Chat IA eliminados: ahora los docs se envían al
            # agente Hermes por mensaje, no desde un bucket.
            resources :ai_chat_storages, only: [:index, :create, :update, :destroy] do
              collection do
                post :test
              end
            end
            # Chat Aprovisionamiento: el usuario (con permiso) le pide al Hermes
            # Provisioner de SU cuenta crear/aprovisionar MCPs. Aislado por cuenta.
            resources :provisioning_chat_messages, only: [:index, :create], controller: 'provisioning_chat_messages' do
              collection do
                get :status
                post :provision
              end
            end
            # Estado del Consumer (Chat IA) + sync de modelos con el Hermes de la cuenta.
            resource :ai_chat_hermes, only: [:show], controller: 'ai_chat_hermes' do
              post :sync_models
              post :connect
              get :tools
            end
            # Cron jobs de Hermes de la cuenta (aislados por el scoped token). Ver + gestionar.
            resources :ai_chat_hermes_cron_jobs, only: [:index, :create, :destroy],
                                                 controller: 'ai_chat_hermes_cron_jobs' do
              patch :toggle, on: :member
            end
            # Permisos granulares de Hermes por usuario (READ/CREATE/WRITE/...) — solo admin del Chat IA.
            resources :hermes_user_permissions, only: [:index, :update], param: :user_id,
                                                controller: 'hermes_user_permissions'
            # Agentes del Hermes de la cuenta (1:1 con usuario, permisos del usuario).
            resources :hermes_agents, only: [:index, :create, :update, :destroy],
                                      controller: 'hermes_agents'
            # Conexiones a los agentes del Hermes de la cuenta (varios agentes, mismo host).
            resources :hermes_connections, only: [:index, :create, :update, :destroy],
                                           controller: 'hermes_connections' do
              collection { get :mine }
              member do
                post :verify
                get :model_options       # modelos que ofrece ese agente
                get :jobs                # cron/tareas del agente
                post :create_job
                post 'jobs/:job_id/pause', action: :pause_job
                post 'jobs/:job_id/resume', action: :resume_job
                post 'jobs/:job_id/run', action: :run_job
                delete 'jobs/:job_id', action: :delete_job
              end
            end
            # Auditoría de acciones ejecutadas por Hermes (solo lectura, admin del Chat IA).
            resources :hermes_action_logs, only: [:index], controller: 'hermes_action_logs'
            resources :response_bot_seats, only: [:index]
            resources :response_bot_roles, only: [:index]
            resources :response_bot_configs, only: [:index, :create, :update, :destroy] do
              collection { post :setup_labels }
            end
            resources :response_bot_documents, only: [:index, :update, :destroy] do
              collection { post :sync }
            end
            resources :affiliates do
              collection { get :portal_login_url }
              member do
                patch :regenerate_token
                patch :regenerate_code
              end
              resources :affiliate_ip_whitelists, only: [:index, :create, :update, :destroy]
            end
            resources :calendar_events, only: [:index, :show, :create, :update, :destroy]
            resources :calendar_external_people, only: [:index, :show, :create, :update, :destroy]
            resources :forms, only: [:index, :show, :create, :update, :destroy]
            resource :form_config, only: [:show, :update]
            resource :reports, only: [], controller: 'reports' do
              collection do
                get :products
                get :agents
                get :dialer
                get :agent_status
                patch :set_dialer_state
              end
            end
            # Per-agent drill-down for the agents report.
            namespace :reports do
              get 'analytics/:metric_key/records', to: 'analytics#records'
              get 'analytics/:metric_key/breakdown', to: 'analytics#breakdown'
            end
            resources :custom_tables, only: [:index, :show, :create, :update, :destroy] do
              collection do
                post :import # import a table definition + columns from exported JSON
              end
              member do
                get :export # export this table's definition + columns as portable JSON
              end
              resources :custom_columns, only: [:index, :create, :update, :destroy]
              # Rows (records) of a standalone table — the "fill the table" surface.
              resources :data, only: [:index, :create, :update, :destroy], controller: 'custom_table_data'
            end
            resources :quick_buttons, only: [:index, :create, :update, :destroy]

            # Tasks (kanban) module
            namespace :tasks do
              resources :boards do
                resources :stages, only: [:index, :create, :update, :destroy] do
                  resources :automations, only: [:index, :create, :update, :destroy],
                                          controller: 'stage_automations'
                end
              end
              resources :tasks do
                member do
                  post :move
                  get :activities
                  get :automation_runs
                end
                resources :automations, only: %i[index create update destroy],
                                        controller: 'automations' do
                  member { post :run_now }
                end
              end
              resources :lead_contacts
            end

            # Bulk WhatsApp (mass template send via CSV -> n8n webhook) module
            namespace :bulk_whatsapp do
              resource :config, only: [:show, :update], controller: 'config'
              resources :batches, only: [:index, :create, :show] do
                collection do
                  get :senders
                  get :lead_fields
                  get :field_values
                  get :analytics
                end
                member do
                  post :reuse
                end
              end
              # Callback de n8n por batch_uuid (autenticado por token, no por admin).
              post 'batches/:batch_uuid/results', to: 'callbacks#results'
            end

            namespace :whatsapp_groups do
              get 'inboxes/:inbox_id/eligibility', to: 'groups#eligibility'
              resources :groups, only: [:index, :show, :create, :update] do
                member do
                  post :invite
                  post :members, action: :add_member
                  delete 'members/:member_id', action: :remove_member
                  patch 'members/:member_id', action: :update_member
                  post :messages, action: :send_message
                end
              end
            end

            namespace :tickets do
              resource :permissions, only: [:show]
              resource :metrics, only: [:show]
              resource :counts, only: [:show]
              resource :notification_preferences, only: [:show, :update]
              resources :categories, only: [:index, :create, :update, :destroy]
              resources :tickets, only: [:index, :show, :create, :update, :destroy] do
                collection do
                  post :bulk_action # asignar/cerrar/archivar varios de una
                end
                member do
                  post :assign
                  post :change_status
                  post :resolve
                  post :reopen
                  post :rate
                  post :restore
                  post :merge # fusionar en otro ticket (duplicados)
                end
                resources :comments, only: [:index, :create]
              end
            end

            # Lead Import (pull leads from external databases) module
            namespace :lead_import do
              resources :sources, only: [:index, :show, :create, :update, :destroy] do
                collection do
                  post :test_connection, action: :test_connection_unsaved
                  get :lead_fields
                  post :create_custom_field
                end
                member do
                  post :test_connection
                  get :tables
                  get :columns
                  post :sync
                  get :sync_status
                end
              end
            end

            # Data Export (mirror account data to an external database) module
            namespace :data_export do
              resources :targets, only: [:index, :show, :create, :update, :destroy] do
                collection do
                  post :test_connection, action: :test_connection_unsaved
                  get :available_groups
                end
                member do
                  post :test_connection
                  post :build_schema
                  post :toggle
                  post :sync_now
                  get :history
                end
              end
            end

            # Analytics & Dashboards (BI) module
            namespace :analytics do
              resources :data_sources do
                member do
                  post :test_connection
                  get :schema
                  get :preview
                  get :column_values
                  post :query
                  post :compile_sql
                  post :custom_sql
                  post :validate_sql
                  post :sync
                end
                collection { post :test_connection, action: :test_connection_unsaved }
                resources :data_source_permissions, only: [:index, :create, :update, :destroy]
              end

              # Cross-source reports: join data across several data sources (e.g.
              # Wimpos' databases on different servers) by a mapped common field.
              resources :cross_reports do
                member { post :execute }
              end

              resources :folders
              resources :dashboards do
                collection do
                  get :overview_stats
                  get :internal_reports
                  post :create_internal_reports
                end
                member do
                  put :layout
                  post :duplicate
                end
                resources :widgets, controller: 'dashboard_widgets' do
                  member { post :execute }
                end
                resources :shares, only: [:index, :create, :update, :destroy]
              end

              resources :exports, only: [:index, :show, :create, :destroy]

              # RBAC / permissions (admin-only)
              resources :roles
              resources :role_permissions, only: [:index, :update]
              resources :user_permissions, only: [:index, :create, :update, :destroy] do
                patch :bulk, on: :collection
              end
              # Per-user dashboard access (which dashboards a single user can see)
              get :user_dashboard_access, to: 'user_dashboard_access#show'
              patch :user_dashboard_access, to: 'user_dashboard_access#update'
              get :my_capabilities, to: 'capabilities#show'
              resources :audit_logs, only: [:index, :show]
            end
          end
        end
      end
      # end of account scoped api routes
      # ----------------------------------

      namespace :jabvox do
        namespace :affiliate_portal do
          post 'auth/login', to: 'auth#login'
          resources :contacts, only: [:create]
          resources :imports, only: [:create]
          resources :leads, only: [:index] do
            collection { get :history }
          end
        end
      end

      namespace :integrations do
        resources :webhooks, only: [:create]
      end

      # Frontend API endpoint to trigger SAML authentication flow
      post 'auth/saml_login', to: 'auth#saml_login'

      resource :profile, only: [:show, :update] do
        delete :avatar, on: :collection
        member do
          post :availability
          post :auto_offline
          put :set_active_account
          post :resend_confirmation
          post :reset_access_token
        end

        # MFA routes
        scope module: 'profile' do
          resource :mfa, controller: 'mfa', only: [:show, :create, :destroy] do
            post :verify
            post :backup_codes
          end
          resources :sessions, only: [:index, :destroy]
        end
      end

      resource :notification_subscriptions, only: [:create, :destroy]

      namespace :widget do
        resource :direct_uploads, only: [:create]
        resource :config, only: [:create]
        resources :campaigns, only: [:index]
        resources :events, only: [:create]
        resources :messages, only: [:index, :create, :update]
        resources :conversations, only: [:index, :create] do
          collection do
            post :destroy_custom_attributes
            post :set_custom_attributes
            post :update_last_seen
            post :toggle_typing
            post :transcript
            get  :toggle_status
          end
        end
        resource :contact, only: [:show, :update] do
          collection do
            post :destroy_custom_attributes
            patch :set_user
          end
        end
        resources :inbox_members, only: [:index]
        resources :labels, only: [:create, :destroy]
        namespace :integrations do
          resource :dyte, controller: 'dyte', only: [] do
            collection do
              post :add_participant_to_meeting
            end
          end
        end
      end
    end

    namespace :v2 do
      resources :accounts, only: [:create] do
        scope module: :accounts do
          resources :summary_reports, only: [] do
            collection do
              get :agent
              get :team
              get :inbox
              get :label
              get :channel
            end
          end
          resources :reports, only: [:index] do
            collection do
              get :summary
              get :bot_summary
              get :agents
              # Panel de WhatsApp por agente (estudio de negocio): tabla por agente,
              # resumen+embudo, rankings, timeline por turnos y export.
              get 'whatsapp/agents', action: :whatsapp_agents
              get 'whatsapp/summary', action: :whatsapp_summary
              get 'whatsapp/rankings', action: :whatsapp_rankings
              get 'whatsapp/conversations/:conversation_id/timeline', action: :whatsapp_timeline
              get 'whatsapp/label_durations', action: :whatsapp_label_durations
              get 'whatsapp/label_leads', action: :whatsapp_label_leads
              get 'whatsapp/templates', action: :whatsapp_templates
              get 'whatsapp/inboxes', action: :whatsapp_inboxes
              get 'whatsapp/agents/:agent_id/detail', action: :whatsapp_agent_detail
              get 'whatsapp/export', action: :whatsapp_export
              # Reporte de Grupos de WhatsApp: resumen y tabla por grupo.
              get 'whatsapp_groups/summary', action: :whatsapp_groups_summary
              get 'whatsapp_groups/list', action: :whatsapp_groups_list
              get :inboxes
              get :labels
              get :teams
              get :conversations
              get :conversations_summary
              get :conversation_traffic
              get :drilldown
              get :bot_metrics
              get :inbox_label_matrix
              get :first_response_time_distribution
              get :outgoing_messages_count
            end
          end
          resource :year_in_review, only: [:show]
          resources :live_reports, only: [] do
            collection do
              get :conversation_metrics
              get :grouped_conversation_metrics
            end
          end
        end
      end
    end
  end

  if JabvoxApp.enterprise?
    namespace :enterprise, defaults: { format: 'json' } do
      namespace :api do
        namespace :v1 do
          resources :accounts do
            member do
              post :checkout
              post :subscription
              post :select_billing_currency
              get :limits
              post :toggle_deletion
              post :topup_checkout
              get :topup_options
            end
          end
        end
      end

      post 'webhooks/stripe', to: 'webhooks/stripe#process_payload'
      post 'webhooks/firecrawl', to: 'webhooks/firecrawl#process_payload'
    end
  end

  # ----------------------------------------------------------------------
  # Routes for platform APIs
  namespace :platform, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :users, only: [:create, :show, :update, :destroy] do
          member do
            get :login
            post :token
          end
        end
        resources :agent_bots, only: [:index, :create, :show, :update, :destroy] do
          delete :avatar, on: :member
        end
        # Aprovisionamiento en un paso (cuenta + admin + módulos + límites) para n8n.
        resource :provisioning, only: [:create], controller: 'provisioning'
        resources :accounts, only: [:index, :create, :show, :update, :destroy] do
          resources :account_users, only: [:index, :create] do
            collection do
              delete :destroy
            end
          end
          resources :email_channel_migrations, only: [:create]
        end
      end
    end
  end

  # ----------------------------------------------------------------------
  # Routes for inbox APIs Exposed to contacts
  namespace :public, defaults: { format: 'json' } do
    namespace :api do
      namespace :v1 do
        resources :inboxes do
          scope module: :inboxes do
            resources :contacts, only: [:create, :show, :update] do
              resources :conversations, only: [:index, :create, :show] do
                member do
                  post :toggle_status
                  post :toggle_typing
                  post :update_last_seen
                end

                resources :messages, only: [:index, :create, :update]
              end
            end
          end
        end

        resources :csat_survey, only: [:show, :update]
      end
    end
  end

  get 'hc/:slug', to: 'public/api/v1/portals#show'
  get 'hc/:slug/sitemap.xml', to: 'public/api/v1/portals#sitemap'
  get 'hc/:slug/:locale', to: 'public/api/v1/portals#show', as: :public_portal_locale
  get 'hc/:slug/:locale/search', to: 'public/api/v1/portals/search#index', as: :portal_search
  get 'hc/:slug/:locale/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/:locale/categories', to: 'public/api/v1/portals/categories#index'
  get 'hc/:slug/:locale/categories/:category_slug', to: 'public/api/v1/portals/categories#show', as: :public_portal_category
  get 'hc/:slug/:locale/categories/:category_slug/articles', to: 'public/api/v1/portals/articles#index'
  get 'hc/:slug/articles/:article_slug.png', to: 'public/api/v1/portals/articles#tracking_pixel'
  get 'hc/:slug/articles/:article_slug.md', to: 'public/api/v1/portals/articles#show_markdown', as: :public_portal_article_markdown,
                                            defaults: { format: :md }
  get 'hc/:slug/articles/:article_slug', to: 'public/api/v1/portals/articles#show', as: :public_portal_article

  # ----------------------------------------------------------------------
  # Used in mailer templates
  resource :app, only: [:index] do
    resources :accounts do
      resources :conversations, only: [:show]
    end
  end

  # ----------------------------------------------------------------------
  # Routes for channel integrations
  mount Facebook::Messenger::Server, at: 'bot'
  get 'webhooks/twitter', to: 'api/v1/webhooks#twitter_crc'
  post 'webhooks/twitter', to: 'api/v1/webhooks#twitter_events'
  # Endpoints públicos (sin autenticación): registro y planes antes del login
  namespace :public do
    post 'register', to: 'registration#create'
    resources :plans, only: [:index, :show]
  end

  # Cobro/aprovisionamiento por pasarela de pago (Bold/Wompi/Mono).
  #   process_payload  <- la pasarela (webhook firmado)
  #   resolve/checkout <- la web de cobro (canal interno autenticado)
  post 'webhooks/jabvox/billing/resolve', to: 'webhooks/jabvox/billing#resolve_token'
  post 'webhooks/jabvox/billing/checkout', to: 'webhooks/jabvox/billing#create_checkout'
  post 'webhooks/jabvox/billing/:gateway', to: 'webhooks/jabvox/billing#process_payload'
  # Callback del Hermes Aprovisionador: confirma que el Hermes de una cuenta ya está operativo.
  post 'webhooks/jabvox/hermes/provisioned', to: 'webhooks/jabvox/hermes#provisioned'
  # El Aprovisionador consulta las conexiones de DB de una cuenta para crear su MCP de analítica.
  get 'webhooks/jabvox/hermes/data_sources/:account_id',
      to: 'webhooks/jabvox/hermes#data_sources'
  get 'webhooks/jabvox/hermes/data_sources/:account_id/:id/credentials',
      to: 'webhooks/jabvox/hermes#credentials'
  # Un agente de Hermes ejecuta acciones sobre Jabvox con su token exclusivo (permisos del agente).
  get 'webhooks/jabvox/hermes_agent/tools', to: 'webhooks/jabvox/hermes_agent#tools'
  post 'webhooks/jabvox/hermes_agent/execute', to: 'webhooks/jabvox/hermes_agent#execute'
  post 'webhooks/line/:line_channel_id', to: 'webhooks/line#process_payload'
  post 'webhooks/telegram/:bot_token', to: 'webhooks/telegram#process_payload'
  post 'webhooks/sms/:phone_number', to: 'webhooks/sms#process_payload'
  get 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#verify'
  post 'webhooks/whatsapp/:phone_number', to: 'webhooks/whatsapp#process_payload'
  get 'webhooks/instagram', to: 'webhooks/instagram#verify'
  post 'webhooks/instagram', to: 'webhooks/instagram#events'
  post 'webhooks/tiktok', to: 'webhooks/tiktok#events'
  post 'webhooks/shopify', to: 'webhooks/shopify#events'

  namespace :twitter do
    resource :callback, only: [:show]
  end

  namespace :linear do
    resource :callback, only: [:show]
  end

  namespace :shopify do
    resource :callback, only: [:show]
  end

  namespace :twilio do
    resources :callback, only: [:create]
    resources :delivery_status, only: [:create]

    if JabvoxApp.enterprise?
      post 'voice/call/:phone', to: 'voice#call_twiml', as: :voice_call
      post 'voice/status/:phone', to: 'voice#status', as: :voice_status
      post 'voice/conference_status/:phone', to: 'voice#conference_status', as: :voice_conference_status
      post 'voice/recording_status/:phone', to: 'voice#recording_status', as: :voice_recording_status
    end
  end

  get 'microsoft/callback', to: 'microsoft/callbacks#show'
  get 'google/callback', to: 'google/callbacks#show'
  get 'instagram/callback', to: 'instagram/callbacks#show'
  get 'tiktok/callback', to: 'tiktok/callbacks#show'
  get 'notion/callback', to: 'notion/callbacks#show'
  # ----------------------------------------------------------------------
  # Routes for external service verifications
  get '.well-known/assetlinks.json' => 'android_app#assetlinks'
  get '.well-known/apple-app-site-association' => 'apple_app#site_association'
  get '.well-known/microsoft-identity-association.json' => 'microsoft#identity_association'
  get '.well-known/cf-custom-hostname-challenge/:id', to: 'custom_domains#verify'

  # ----------------------------------------------------------------------
  # Internal Monitoring Routes
  require 'sidekiq/web'
  require 'sidekiq/cron/web'

  devise_for :super_admins, path: 'super_admin', controllers: { sessions: 'super_admin/devise/sessions' }
  devise_scope :super_admin do
    get 'super_admin/logout', to: 'super_admin/devise/sessions#destroy'
    namespace :super_admin do
      root to: 'dashboard#index'

      resource :app_config, only: [:show, :create]
      # Administración central de instancias Hermes por cuenta (todo vía el Provisionador).
      # OJO: es un panel custom, NO un recurso Administrate. Debe estar en `hidden_resources`
      # del nav (_navigation.html.erb) para que Administrate no le exija un Dashboard.
      resources :hermes_instances, only: [:index], param: :account_id do
        collection do
          post :connect_provisioner   # conectar el Hermes Aprovisionador global
        end
        member do
          post :provision
          post :disable
          post :restart
          post :rotate
          post :link_account          # ligar el aprovisionador a esta cuenta
          post :unlink_account
        end
      end
      resource :push_diagnostics, only: [:show, :create] do
        post :destroy_subscriptions, on: :collection
      end

      # order of resources affect the order of sidebar navigation in super admin
      # Cobro/aprovisionamiento por pasarela de pago.
      resources :jabvox_plans
      resources :jabvox_payment_gateway_configs, except: [:destroy]
      resource :jabvox_billing_config, only: [:edit, :update]
      resources :jabvox_provisioning_transactions, only: [:index, :show] do
        post :retry_provisioning, on: :member
        post :mark_paid_manually, on: :member
      end
      # Softphone WebRTC: configuración por cuenta + extensiones ligadas a usuarios.
      resources :jabvox_softphone_configs
      resources :jabvox_softphone_extensions do
        get :status, on: :collection
      end
      resources :jabvox_saldo_configs, only: [:index, :new, :create, :destroy]
      resources :jabvox_ticket_helpdesk_configs
      resources :jabvox_response_bot_seats
      resources :jabvox_response_bot_roles
      resources :jabvox_deleted_leads, only: [:index, :show] do
        member { post :restore }
      end

      resources :accounts, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        post :seed, on: :member
        post :reset_cache, on: :member
        post :provision_ssl_form_config, on: :member
        delete :revoke_domain_form_config, on: :member
        resource :jabvox_saldo_config, only: [:show, :update]
        resources :jabvox_ip_whitelists, only: [:index, :create, :destroy] do
          patch :toggle, on: :member
        end
        # Módulo de flujos por cuenta: activar/desactivar y tope de flujos.
        resources :account_automations, only: [:index] do
          patch :toggle, on: :collection
          patch :update_limit, on: :collection
        end
        resources :jabvox_user_extensions, only: [:index, :create, :destroy]
      end
      resources :users, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end

      resources :access_tokens, only: [:index, :show]
      resources :installation_configs, only: [:index, :new, :create, :show, :edit, :update]
      resources :agent_bots, only: [:index, :new, :create, :show, :edit, :update, :destroy] do
        delete :avatar, on: :member, action: :destroy_avatar
      end
      resources :platform_apps, only: [:index, :new, :create, :show, :edit, :update, :destroy]
      resources :platform_banners
      resource :instance_status, only: [:show]

      resource :settings, only: [:show] do
        get :refresh, on: :collection
      end

      # resources that doesn't appear in primary navigation in super admin
      resources :account_users, only: [:new, :create, :show, :destroy]
    end
    authenticated :super_admin do
      mount Sidekiq::Web => '/monitoring/sidekiq'
    end
  end

  namespace :installation do
    get 'onboarding', to: 'onboarding#index'
    post 'onboarding', to: 'onboarding#create'
  end

  # ---------------------------------------------------------------------
  # Routes for swagger docs
  get '/swagger/*path', to: 'swagger#respond'
  get '/swagger', to: 'swagger#respond'

  # ----------------------------------------------------------------------
  # Routes for testing
  resources :widget_tests, only: [:index] unless Rails.env.production?
end
