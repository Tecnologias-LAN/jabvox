# frozen_string_literal: true

module Jabvox
  class DialerContactPickerService
    def initialize(account, campaign)
      @account = account
      @campaign = campaign
    end

    # Returns the next lead to dial, or nil when there is nothing to dial.
    # Defense in depth: an out-of-window campaign never yields a lead.
    def pick
      return nil unless @campaign.in_schedule?

      @campaign.dial_mode_jabvox == 'one_by_one' ? pick_one_by_one : pick_by_last_state
    end

    # Atomically picks the next lead AND reserves it by creating its
    # "calling" campaign-contact row, so two agents dialing the same campaign
    # can never grab the same lead (predictive mode = many concurrent agents).
    # A per-campaign Postgres advisory lock serializes only the short
    # pick+insert window; the slow AMI Originate happens later, outside it.
    # `attributes_for` receives the picked lead and returns the row attrs
    # (the controller resolves the dial number, which may reject the lead).
    # Returns [lead, campaign_contact] or [nil, nil].
    def pick_and_reserve
      return [nil, nil] unless @campaign.in_schedule?

      ApplicationRecord.transaction do
        ApplicationRecord.connection.execute(
          "SELECT pg_advisory_xact_lock(#{LOCK_NAMESPACE}, #{@campaign.id.to_i})"
        )
        lead = pick
        return [nil, nil] if lead.nil?

        attrs = yield(lead)
        # A nil from the block means "skip this lead" (e.g. no dial number);
        # still reserve it so the next call moves on instead of re-picking it.
        attrs ||= { status_jabvox: 'failed' }

        # Reuse the existing row on a retry (same lead re-entering the queue) so we
        # never create duplicate campaign-contacts; bump attempts. New leads start
        # at attempt 1.
        contact = @campaign.jabvox_dialer_campaign_contacts.find_or_initialize_by(contact_id: lead.contact_id)
        contact.account_id = @account.id
        contact.attempts_jabvox = contact.attempts_jabvox.to_i + 1
        contact.last_attempt_at_jabvox = Time.current
        contact.assign_attributes(attrs)
        contact.save!
        [lead, contact]
      end
    end

    private

    # Arbitrary constant so advisory locks here never collide with other features.
    LOCK_NAMESPACE = 0x4A42 # "JB"

    def base_scope
      DialerLeadsFilterService.for_campaign(@account, @campaign, require_phone: true)
                              .scope.includes(:contact)
    end

    # Historical behavior: any matching lead, at random (a lead may be dialed
    # again on later passes — the last-management filter decides eligibility).
    # Excluye los contactos con una llamada EN CURSO (campaign_contact en
    # 'calling') para que dos agentes no marquen al mismo cliente a la vez: el
    # advisory lock serializa el pick, pero sin esta exclusión el siguiente pick
    # podía volver a elegir el mismo lead legítimamente.
    def pick_by_last_state
      scope = base_scope
      calling_ids = @campaign.jabvox_dialer_campaign_contacts
                             .where(status_jabvox: 'calling').where.not(contact_id: nil)
                             .pluck(:contact_id)
      scope = scope.where.not(jabvox_leads: { contact_id: calling_ids }) if calling_ids.any?
      scope.order('RANDOM()').first
    end

    # One-by-one with optional retries:
    # 1) Leads never dialed in this campaign go first (stable id order).
    # 2) If none are left, retry leads whose LAST outcome is a retry status
    #    (e.g. no_answer/busy/failed) and that haven't hit max_retries — oldest
    #    attempt first, so retries land at the END of the queue.
    # A lead is "done" (never re-picked) once it answers, completes, or exhausts
    # its retries. Returns the JabvoxLead to dial, or nil.
    def pick_one_by_one
      fresh = fresh_lead
      return fresh if fresh

      retry_lead
    end

    # Leads with no campaign-contact row yet.
    def fresh_lead
      dialed_ids = @campaign.jabvox_dialer_campaign_contacts
                            .where.not(contact_id: nil).distinct.pluck(:contact_id)
      scope = base_scope
      scope = scope.where.not(jabvox_leads: { contact_id: dialed_ids }) if dialed_ids.any?
      scope.order('jabvox_leads.id ASC').first
    end

    # Leads eligible for a retry, oldest attempt first (they go last).
    def retry_lead
      statuses = Array(@campaign.retry_statuses_jabvox)
      return nil if statuses.empty?

      max = @campaign.max_retries_jabvox.to_i
      cc = @campaign.jabvox_dialer_campaign_contacts
                    .where(status_jabvox: statuses)
                    .order(last_attempt_at_jabvox: :asc)
      # max_retries == 0 significa "sin tope": omitimos la cláusula en vez de
      # bindear Float::INFINITY, que Postgres rechaza contra una columna integer
      # (PG::InvalidTextRepresentation) y abortaba la transacción de reserva.
      cc = cc.where('attempts_jabvox <= ?', max) if max.positive?
      # Respetar el intervalo de reintento configurado: un lead no se re-marca
      # antes de retry_interval_jabvox minutos desde su último intento (evita
      # re-marcar al mismo cliente cada pocos segundos en el siguiente tick).
      interval = @campaign.retry_interval_jabvox.to_i
      cc = cc.where('last_attempt_at_jabvox IS NULL OR last_attempt_at_jabvox <= ?', interval.minutes.ago) if interval.positive?
      cc = cc.first
      return nil if cc.nil?

      # Only re-dial if the lead still passes the campaign filters and has a phone.
      base_scope.find_by(contact_id: cc.contact_id)
    end
  end
end
