# frozen_string_literal: true

require 'rails_helper'

# El ciclo de cuota se cierra solo: al AMPLIAR storage_gb (upgrade de plan) se encola
# la regularización que promueve los excedentes.
RSpec.describe Account, 'drive regularization hook' do
  include ActiveJob::TestHelper

  let(:account) { create(:account, jabvox_drive_enabled_jabvox: true, limits: { 'storage_gb' => 1 }) }

  it 'encola la regularización al AUMENTAR la cuota' do
    expect do
      account.update!(limits: { 'storage_gb' => 5 })
    end.to have_enqueued_job(Jabvox::Drive::QuotaRegularizationJob).with(account.id)
  end

  it 'NO encola al reducir la cuota' do
    expect do
      account.update!(limits: { 'storage_gb' => 0 })
    end.not_to have_enqueued_job(Jabvox::Drive::QuotaRegularizationJob)
  end

  it 'NO encola si el Drive está desactivado' do
    account.update!(jabvox_drive_enabled_jabvox: false)
    expect do
      account.update!(limits: { 'storage_gb' => 9 })
    end.not_to have_enqueued_job(Jabvox::Drive::QuotaRegularizationJob)
  end
end
