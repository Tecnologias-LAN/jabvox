# frozen_string_literal: true

module Jabvox
  module Reports
    # Builds report seed data. Dev/test only — invoked from the jabvox:reports
    # rake tasks. Not loaded on the hot path.
    class SeedBuilder
      CHANNELS = %w[Channel::WebWidget Channel::Api Channel::Email].freeze

      def initialize(account:, days:, per_day:)
        @account = account
        @days = days
        @per_day = per_day
        @zone = TimeRange.account_zone(account)
      end

      def run
        ensure_base!
        puts "Seeding #{@days} days x ~#{@per_day}/day for account ##{@account.id}…"
        @days.times do |offset|
          day = @zone.today - offset
          seed_day(day)
          print '.' if (offset % 10).zero?
        end
        puts "\nDone. Totals:"
        report_totals
      end

      # Fast bulk message insert for load testing (no per-row callbacks).
      def bulk_messages!(total)
        ensure_base!
        conv = @conversations.first
        inbox = @inboxes.first
        user = @agents.first
        puts "Bulk-inserting #{total} messages…"
        batch = 10_000
        (total / batch).times do |b|
          rows = Array.new(batch) do |i|
            secs = ((b * batch + i) % (@days * 86_400))
            ts = Time.current - secs.seconds
            { account_id: @account.id, inbox_id: inbox.id, conversation_id: conv.id,
              message_type: 1, private: false, status: [0, 1, 2, 3].sample,
              sender_type: 'User', sender_id: user.id, content: "carga #{b}-#{i}",
              content_type: 0, created_at: ts, updated_at: ts }
          end
          Message.insert_all(rows)
          print "\r#{(b + 1) * batch}"
        end
        puts "\nDone."
      end

      private

      def ensure_base!
        @agents = @account.users.to_a
        @agents = [create_user!] if @agents.empty?
        @inboxes = ensure_inboxes
        @contacts = ensure_contacts
        @conversations = ensure_conversations
        @states = ensure_management_states
        ensure_dialer
        ensure_app_states
        ensure_products
      end

      # A small product catalog so order items (and the product breakdown/filter)
      # have data.
      def ensure_products
        @products = @account.jabvox_products.limit(8).to_a
        return @products if @products.size >= 5

        %w[Plan\ Básico Plan\ Pro Plan\ Premium Instalación Soporte Capacitación].each do |name|
          @products << @account.jabvox_products.find_or_create_by!(name_jabvox: name) do |p|
            p.price_jabvox = rand(20_000..500_000)
            p.product_type_jabvox = %w[product service].sample
            p.created_by_id = @agents.first.id
          end
        end
        @products
      end

      # Seed app states + per-agent state logs so the "Tiempo por estado" table
      # renders. Covers the mixed cases that surface the "some agents show, some
      # don't" behavior: an agent with several CLOSED logs, an agent with an
      # OPEN log (currently in a state), and an agent with NO logs at all.
      def ensure_app_states
        @app_states = @account.jabvox_app_states.ordered.to_a
        if @app_states.empty?
          @app_states = [
            { name: 'Almuerzo', color: '#f59e0b' },
            { name: 'Baño', color: '#8b5cf6' },
            { name: 'Capacitación', color: '#3b82f6' },
          ].map.with_index do |s, i|
            @account.jabvox_app_states.create!(name: s[:name], color: s[:color],
                                               position: i, created_by_id: @agents.first.id)
          end
        end
        return if JabvoxAppStateLog.where(account_id: @account.id).exists?

        seed_state_logs
      end

      def seed_state_logs
        agents = @agents
        # Agent 0: several CLOSED logs over the last 10 days.
        first = agents[0]
        10.times do |d|
          day = @zone.today - d
          3.times do |k|
            started = @zone.local(day.year, day.month, day.day, 9 + k * 2, 0, 0).utc
            ended = started + rand(15..90).minutes
            JabvoxAppStateLog.create!(account_id: @account.id, user_id: first.id,
                                      app_state_id: @app_states.sample.id,
                                      started_at: started, ended_at: ended)
          end
        end
        # Agent 1 (if any): one OPEN log (currently in a state) + also set the
        # account_user current state so the live column has something to show.
        second = agents[1]
        return unless second

        open_started = (Time.current - 40.minutes).utc
        JabvoxAppStateLog.create!(account_id: @account.id, user_id: second.id,
                                  app_state_id: @app_states.first.id,
                                  started_at: open_started, ended_at: nil)
        AccountUser.where(account_id: @account.id, user_id: second.id)
                   .update_all(jabvox_app_state_id: @app_states.first.id,
                               jabvox_app_state_changed_at: open_started)
      end

      # A dialer campaign + a pool of campaign contacts, so calls can be seeded
      # into jabvox_dialer_call_logs (the source the agents report counts).
      def ensure_dialer
        @campaign = @account.jabvox_dialer_campaigns.first ||
                    @account.jabvox_dialer_campaigns.create!(
                      name_jabvox: 'Campaña Reportes', status_jabvox: 'draft',
                      dial_mode_jabvox: 'one_by_one', max_concurrent_jabvox: 1,
                      retry_count_jabvox: 0, retry_interval_jabvox: 60, max_retries_jabvox: 0
                    )
        @campaign_contacts = JabvoxDialerCampaignContact.where(jabvox_dialer_campaign_id: @campaign.id).limit(30).to_a
        return if @campaign_contacts.size >= 20

        @contacts.first(20).each do |contact|
          @campaign_contacts << JabvoxDialerCampaignContact.find_or_create_by!(
            jabvox_dialer_campaign_id: @campaign.id, contact_id: contact.id
          ) do |cc|
            cc.account_id = @account.id
            cc.phone_jabvox = contact.phone_number.presence || "+57300#{rand(1_000_000..9_999_999)}"
            cc.status_jabvox = 'pending'
          end
        end
      end

      def create_user!
        user = User.create!(name: 'Agente Reportes', email: "reportes-#{SecureRandom.hex(4)}@jabvox.test",
                            password: SecureRandom.hex(12))
        AccountUser.create!(account: @account, user: user, role: :agent)
        user
      end

      def ensure_inboxes
        return @account.inboxes.to_a if @account.inboxes.any?

        CHANNELS.map.with_index do |type, i|
          channel = build_channel(type)
          @account.inboxes.create!(name: "Bandeja #{i + 1}", channel: channel)
        end
      end

      def build_channel(type)
        case type
        when 'Channel::WebWidget'
          Channel::WebWidget.create!(account: @account, website_url: 'https://demo.jabvox.test')
        when 'Channel::Api'
          Channel::Api.create!(account: @account, identifier: SecureRandom.hex(6))
        else
          Channel::Email.create!(account: @account, email: "inbox-#{SecureRandom.hex(4)}@jabvox.test",
                                 forward_to_email: "fwd-#{SecureRandom.hex(4)}@jabvox.test")
        end
      end

      def ensure_contacts
        existing = @account.contacts.limit(50).to_a
        return existing if existing.size >= 50

        (50 - existing.size).times do |i|
          c = @account.contacts.create!(name: "Lead #{SecureRandom.hex(3)} #{i}",
                                        phone_number: "+57300#{rand(1_000_000..9_999_999)}",
                                        email: "lead-#{SecureRandom.hex(4)}@jabvox.test")
          JabvoxLead.find_or_create_by!(account: @account, contact: c) do |lead|
            lead.lead_number = (@account.jabvox_leads.maximum(:lead_number) || 0) + 1
          end
          existing << c
        end
        existing
      end

      def ensure_conversations
        existing = @account.conversations.limit(40).to_a
        return existing if existing.size >= 40

        (40 - existing.size).times do
          inbox = @inboxes.sample
          contact = @contacts.sample
          ci = ContactInbox.create!(contact: contact, inbox: inbox, source_id: SecureRandom.uuid)
          conv = Conversation.create!(account: @account, inbox: inbox, contact: contact,
                                      contact_inbox: ci, assignee: @agents.sample)
          existing << conv
        end
        existing
      end

      def ensure_management_states
        return @account.jabvox_management_states.to_a if @account.jabvox_management_states.any?

        %w[Interesado Contactado Vendido].map do |name|
          @account.jabvox_management_states.create!(name_jabvox: name, created_by_id: @agents.first.id)
        end
      end

      def seed_day(day)
        base = @zone.local(day.year, day.month, day.day, 9, 0, 0)
        @per_day.times do
          ts = base + rand(0..(9 * 3600)).seconds
          dispatch_random_event(ts.utc)
        end
      end

      # Weighted mix roughly resembling real traffic.
      def dispatch_random_event(ts)
        case rand(100)
        when 0..44 then seed_message(ts, status: [0, 1, 2].sample)  # sent ok
        when 45..49 then seed_message(ts, status: 3)                 # failed
        when 50..59 then seed_note(ts)
        when 60..69 then seed_management(ts)
        when 70..77 then seed_order(ts)
        when 78..87 then seed_call(ts)
        when 88..93 then seed_resolved(ts)
        else seed_label(ts)
        end
      end

      def seed_message(ts, status:)
        conv = @conversations.sample
        attrs = status == 3 ? { external_error: 'Número no válido (WhatsApp 470)' } : {}
        Message.insert_all([{ account_id: @account.id, inbox_id: conv.inbox_id, conversation_id: conv.id,
                              message_type: 1, private: false, status: status, sender_type: 'User',
                              sender_id: @agents.sample.id, content: "Mensaje al lead #{SecureRandom.hex(3)}",
                              content_type: 0, content_attributes: attrs.to_json, created_at: ts, updated_at: ts }])
      end

      def seed_note(ts)
        conv = @conversations.sample
        Message.insert_all([{ account_id: @account.id, inbox_id: conv.inbox_id, conversation_id: conv.id,
                              message_type: 1, private: true, status: 0, sender_type: 'User',
                              sender_id: @agents.sample.id, content: "Nota interna #{SecureRandom.hex(3)}",
                              content_type: 0, created_at: ts, updated_at: ts }])
      end

      def seed_management(ts)
        conv = @conversations.sample
        msg = Message.create!(account_id: @account.id, inbox_id: conv.inbox_id, conversation_id: conv.id,
                              message_type: 1, private: true, sender_type: 'User', sender_id: @agents.sample.id,
                              content: 'Gestión registrada', content_type: 0, created_at: ts)
        JabvoxManagementAnswer.create!(account_id: @account.id, message_id: msg.id,
                                       jabvox_management_state_id: @states.sample.id,
                                       created_by_id: msg.sender_id, label: 'Resultado',
                                       value: %w[Interesado Rechazó Recontactar].sample, created_at: ts)
      end

      def seed_order(ts)
        conv = @conversations.sample
        order = JabvoxOrder.create!(account_id: @account.id, contact_id: conv.contact_id,
                                    conversation_id: conv.id, doc_type: %w[QUOTE SALE].sample,
                                    status: %w[draft confirmed paid].sample, total: 0, subtotal: 0,
                                    created_by_id: @agents.sample.id, created_at: ts)
        total = 0
        rand(1..3).times do
          product = @products.sample
          qty = rand(1..5)
          line = product.price_jabvox * qty
          total += line
          JabvoxOrderItem.create!(jabvox_order_id: order.id, jabvox_product_id: product.id,
                                  name_snapshot: product.name_jabvox, unit_price: product.price_jabvox,
                                  quantity: qty, line_total: line, created_at: ts)
        end
        order.update_columns(total: total, subtotal: total)
      end

      def seed_call(ts)
        cc = @campaign_contacts.sample
        JabvoxDialerCallLog.create!(
          account_id: @account.id, jabvox_dialer_campaign_id: @campaign.id,
          jabvox_dialer_campaign_contact_id: cc.id, agent_id_jabvox: @agents.sample.id,
          phone_jabvox: cc.phone_jabvox, status_jabvox: %w[answered busy no_answer failed].sample,
          duration_jabvox: rand(0..600), lead_answered_jabvox: [true, false].sample,
          started_at_jabvox: ts, ended_at_jabvox: ts + rand(10..400).seconds,
          notes_jabvox: (['Cliente interesado', 'No contesta', nil].sample),
          created_at: ts
        )
      end

      def seed_resolved(ts)
        conv = @conversations.sample
        ReportingEvent.create!(account_id: @account.id, name: 'conversation_resolved',
                               conversation_id: conv.id, inbox_id: conv.inbox_id,
                               user_id: @agents.sample.id, value: rand(60..7200), created_at: ts)
      end

      def seed_label(ts)
        conv = @conversations.sample
        label = %w[urgente vip seguimiento cerrado].sample
        removed = rand(2).zero? ? ts + rand(1..48).hours : nil
        JabvoxConversationLabelLog.create!(account_id: @account.id, conversation_id: conv.id,
                                           label_jabvox: "#{label}-#{SecureRandom.hex(2)}",
                                           applied_at_jabvox: ts, removed_at_jabvox: removed, created_at: ts)
      end

      def report_totals
        puts "  messages: #{Message.where(account_id: @account.id).count}"
        puts "  orders:   #{JabvoxOrder.where(account_id: @account.id).count}"
        puts "  mgmt:     #{JabvoxManagementAnswer.where(account_id: @account.id).count}"
        puts "  cdr:      #{JabvoxCdrRecord.where(account_id: @account.id).count}"
        puts "  resolved: #{ReportingEvent.where(account_id: @account.id, name: 'conversation_resolved').count}"
        puts "  labels:   #{JabvoxConversationLabelLog.where(account_id: @account.id).count}"
      end
    end
  end
end
