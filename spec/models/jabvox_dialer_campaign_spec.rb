# frozen_string_literal: true

require 'rails_helper'

# Regresión de validaciones de la auditoría del dialer (D-32).
RSpec.describe JabvoxDialerCampaign do
  let(:account) { create(:account) }

  def build_campaign(attrs = {})
    described_class.new({ account_id: account.id, name_jabvox: 'X', status_jabvox: 'draft',
                          dial_mode_jabvox: 'one_by_one' }.merge(attrs))
  end

  it 'rechaza max_retries negativo' do
    expect(build_campaign(max_retries_jabvox: -1)).not_to be_valid
  end

  it 'acepta max_retries = 0 (sin tope)' do
    expect(build_campaign(max_retries_jabvox: 0)).to be_valid
  end

  it 'rechaza retry_statuses con valores fuera de la lista permitida' do
    c = build_campaign(retry_statuses_jabvox: %w[no_answer contestada])
    expect(c).not_to be_valid
    expect(c.errors[:retry_statuses_jabvox]).to be_present
  end

  it 'acepta retry_statuses válidos' do
    expect(build_campaign(retry_statuses_jabvox: %w[no_answer busy failed])).to be_valid
  end
end
