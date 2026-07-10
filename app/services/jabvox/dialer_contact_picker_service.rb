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

    private

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
