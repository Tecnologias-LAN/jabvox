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
        contact = JabvoxDialerCampaignContact.create!(
          {
            account_id: @account.id, jabvox_dialer_campaign_id: @campaign.id,
            contact_id: lead.contact_id, last_attempt_at_jabvox: Time.current
          }.merge(attrs)
        )
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
    def pick_by_last_state
      base_scope.order('RANDOM()').first
    end

    # Walk every matching lead exactly once: skip leads that already have a
    # campaign-contact row in THIS campaign (already attempted), and take the
    # next by a stable order so the pass is deterministic and never repeats.
    def pick_one_by_one
      dialed_lead_ids = @campaign.jabvox_dialer_campaign_contacts
                                 .where.not(contact_id: nil)
                                 .distinct
                                 .pluck(:contact_id)
      scope = base_scope
      scope = scope.where.not(jabvox_leads: { contact_id: dialed_lead_ids }) if dialed_lead_ids.any?
      scope.order('jabvox_leads.id ASC').first
    end
  end
end
