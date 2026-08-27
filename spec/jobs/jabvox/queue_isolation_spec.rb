# frozen_string_literal: true

require 'rails_helper'
require 'yaml'
require 'erb'

# Protege el AISLAMIENTO de colas: cada carga pesada de Jabvox debe ir a su cola
# dedicada (jabvox_*) y nunca a las colas de mensajes/interactivas del worker
# principal. Así una avalancha (p. ej. sync de leads que dispara miles de exports)
# no puede taponar las bandejas. Ver deploy/workers/README.md.
# rubocop:disable RSpec/DescribeClass
RSpec.describe 'Aislamiento de colas Sidekiq de Jabvox' do
  # Cargas pesadas -> su cola dedicada.
  let(:heavy_jobs) do
    {
      'Jabvox::ExternalExport::WriteJob' => 'jabvox_export',
      'Jabvox::ExternalExport::DrainJob' => 'jabvox_export',
      'Jabvox::ExternalExport::BackfillJob' => 'jabvox_export',
      'Jabvox::ExternalExport::StaleSyncReaperJob' => 'jabvox_export',
      'Jabvox::LeadImport::SyncJob' => 'jabvox_lead_import',
      'Jabvox::LeadImport::PurgeTrashJob' => 'jabvox_lead_import',
      'Jabvox::LeadImport::StaleSyncReaperJob' => 'jabvox_lead_import',
      'Jabvox::BulkWhatsappDeliverJob' => 'jabvox_meta',
      'Jabvox::WhatsappTemplatesSyncAllJob' => 'jabvox_meta',
      'Jabvox::CdrSyncJob' => 'jabvox_cdr',
      'Jabvox::CdrSyncAccountJob' => 'jabvox_cdr',
      'Jabvox::AnalyzeCdrCallJob' => 'jabvox_cdr',
      'Jabvox::ProcessAudioJob' => 'jabvox_media',
      'Jabvox::AnalyzeAudioFileJob' => 'jabvox_media',
      'Jabvox::Analytics::ExportJob' => 'jabvox_analytics',
      'Jabvox::VoiceBroadcast::TickJob' => 'jabvox_broadcast',
      'Jabvox::VoiceBroadcast::TickAccountJob' => 'jabvox_broadcast',
      'Jabvox::DialerQueueReaperJob' => 'jabvox_ami',
      'Jabvox::DialerStaleCallReaperJob' => 'jabvox_ami',
      'Jabvox::DialerQueueReconcileAccountJob' => 'jabvox_ami',
      # Click-to-call: cola PROPIA, separada del dialer (interactivo, no debe
      # esperar detrás de los reapers).
      'Jabvox::CaptureClickToCallUniqueidJob' => 'jabvox_click_to_call',
      # Advanced Automations: HTTP saliente a la app externa, reintentos aislados.
      'Jabvox::Automations::ProvisionJob' => 'jabvox_automations'
    }
  end

  # Colas del worker principal (mensajes / interactivo). La avalancha NO debe caer aquí.
  let(:message_queues) { %w[critical high medium default low mailers] }

  # Colas atendidas por cada worker dedicado (leídas de sus configs reales).
  let(:workers) do
    Dir['config/sidekiq_*.yml'].to_h do |f|
      cfg = YAML.safe_load(ERB.new(File.read(f)).result, permitted_classes: [Symbol], aliases: true)
      [File.basename(f), Array(cfg[:queues])]
    end
  end

  it 'cada carga pesada usa su cola dedicada, nunca la de mensajes' do
    heavy_jobs.each do |klass, expected_queue|
      queue = klass.constantize.new.queue_name
      expect(queue).to eq(expected_queue), "#{klass} en #{queue}, esperaba #{expected_queue}"
      expect(message_queues).not_to include(queue)
    end
  end

  it 'los mensajes entrantes van a una cola del worker principal' do
    expect(message_queues).to include(Webhooks::WhatsappEventsJob.new.queue_name)
  end

  it 'cada cola jabvox_* tiene exactamente un worker dedicado que la drena' do
    heavy_jobs.values.uniq.each do |q|
      drainers = workers.select { |_w, qs| qs.include?(q) }.keys
      expect(drainers.size).to eq(1), "#{q} drenada por #{drainers.inspect} (debe ser 1)"
    end
  end

  it 'el worker principal NO drena ninguna cola jabvox_*' do
    main = YAML.safe_load(ERB.new(File.read('config/sidekiq.yml')).result,
                          permitted_classes: [Symbol], aliases: true)[:queues]
    expect(main.grep(/\Ajabvox_/)).to be_empty
  end
end
# rubocop:enable RSpec/DescribeClass
