# frozen_string_literal: true

FactoryBot.define do
  factory :jabvox_softphone_config do
    account
    enabled { true }
    wss_url { 'wss://pbx.jabvox.com:8089/ws' }
    sip_domain { 'pbx.jabvox.com' }
    codecs { %w[opus alaw] }
    dtmf_mode { 'rfc2833' }
    turn_url { 'turn:pbx.jabvox.com:3478' }
    turn_secret { 'turn-secret-123' }
    stun_servers { ['stun:pbx.jabvox.com:3478'] }
  end

  factory :jabvox_softphone_extension do
    account
    user
    sip_secret { 'sip-secret-abc' }
    webrtc_enabled { true }
  end

  factory :jabvox_user_extension do
    account
    user
    sequence(:extension_jabvox) { |n| (1000 + n).to_s }
  end

  factory :jabvox_softphone_call_log do
    account
    user
    phone_number { '3001234567' }
    extension { '1001' }
    direction { :outbound }
    status { :ended }
    duration_seconds { 42 }
  end
end
