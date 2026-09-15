require 'rails_helper'

RSpec.describe Messages::AudioTranscriptionService, type: :service do
  let(:account) { create(:account) }
  let(:conversation) { create(:conversation, account: account) }
  let(:message) { create(:message, account: account, conversation: conversation) }
  let(:attachment) { message.attachments.create!(account: account, file_type: :audio) }

  # El mismo hook que usa Hermes para redactar/resumir/chatear (Ajustes > Integraciones >
  # Jabvox IA). Sin él, la cuenta no tiene ninguna IA conectada.
  def create_jabvox_ia_hook!(api_key: 'test-api-key', base_url: nil)
    Integrations::Hook.create!(
      account: account, app_id: 'jabvox_ia', hook_type: :account, status: :enabled,
      settings: { 'api_key' => api_key, 'base_url' => base_url }.compact
    )
  end

  before do
    account.update!(jabvox_ai_chat_enabled_jabvox: true)
    # El hook valida la key contra el proveedor al crearse/activarse (Integrations::Hook);
    # aquí no probamos esa validación, solo que el servicio use el hook ya conectado.
    allow(Integrations::Openai::KeyValidator).to receive(:validate)
      .and_return(Integrations::Openai::KeyValidator::Result.new(valid: true, code: 200, message: 'Conectado.'))
  end

  describe '#perform' do
    let(:service) { described_class.new(attachment) }

    context 'when the AI module (Chat IA / Hermes) is not enabled' do
      before do
        create_jabvox_ia_hook!
        account.update!(jabvox_ai_chat_enabled_jabvox: false)
      end

      it 'errors without calling the API' do
        expect(service).not_to receive(:transcribe_audio)
        expect(service.perform).to eq({ error: 'No hay ninguna IA conectada. Configúrala en Ajustes > Integraciones > Jabvox IA.' })
      end
    end

    context 'when the account has not connected any AI provider' do
      it 'errors without calling the API' do
        expect(service).not_to receive(:transcribe_audio)
        expect(service.perform).to eq({ error: 'No hay ninguna IA conectada. Configúrala en Ajustes > Integraciones > Jabvox IA.' })
      end
    end

    context 'when transcription is successful' do
      before do
        create_jabvox_ia_hook!
        allow(service).to receive(:transcribe_audio).and_return('Hello world transcription')
      end

      it 'returns successful transcription' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Hello world transcription' })
      end
    end

    context 'when attachment already has transcribed text' do
      before do
        create_jabvox_ia_hook!
        attachment.update!(meta: { transcribed_text: 'Existing transcription' })
      end

      it 'returns existing transcription without calling API' do
        result = service.perform
        expect(result).to eq({ success: true, transcriptions: 'Existing transcription' })
      end
    end

    context 'when the audio exceeds Whisper byte limit' do
      before do
        create_jabvox_ia_hook!
        attachment.file.attach(
          io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
          filename: 'large.mp3',
          content_type: 'audio/mpeg'
        )
        allow(attachment.file.blob).to receive(:byte_size).and_return(described_class::TRANSCRIPTION_BYTE_LIMIT + 1)
      end

      it 'returns an error without calling Whisper' do
        expect(service).not_to receive(:transcribe_audio)
        expect(service.perform).to eq({ error: 'Audio too large for Whisper' })
      end
    end
  end

  describe '#fetch_audio_file' do
    let(:service) { described_class.new(attachment) }

    before do
      attachment.file.attach(
        io: File.open(Rails.public_path.join('audio/widget/ding.mp3')),
        filename: 'speech',
        content_type: 'audio/mpeg'
      )
    end

    it 'adds extension from content type when filename has no extension' do
      temp_file_path = service.send(:fetch_audio_file)

      expect(File.extname(temp_file_path)).to eq('.mpeg')
    ensure
      FileUtils.rm_f(temp_file_path) if temp_file_path.present?
    end
  end

  describe '#transcribe_audio' do
    let(:service) { described_class.new(attachment) }
    let(:audio_api) { double('audio_api') } # rubocop:disable RSpec/VerifiedDoubles
    let(:audio_file_path) { Rails.root.join('tmp/audio_transcription_service_spec.mp3').to_s }

    before do
      create_jabvox_ia_hook!
      File.binwrite(audio_file_path, 'audio')
      allow(service).to receive(:fetch_audio_file).and_return(audio_file_path)
      allow(service).to receive(:update_transcription)
      allow(service.send(:client)).to receive(:audio).and_return(audio_api)
    end

    after do
      FileUtils.rm_f(audio_file_path)
    end

    it 'transcribes with Whisper using the account hook credential' do
      expect(audio_api).to receive(:transcribe).with(
        parameters: hash_including(model: 'whisper-1', temperature: 0.0)
      ).and_return({ 'text' => 'Audio transcript' })

      expect(service.send(:transcribe_audio)).to eq('Audio transcript')
    end
  end

  describe '#client' do
    let(:service) { described_class.new(attachment) }

    it 'uses the base_url from the hook when present' do
      create_jabvox_ia_hook!(base_url: 'https://mi-proveedor.example.com')

      expect(OpenAI::Client).to receive(:new).with(
        access_token: 'test-api-key', uri_base: 'https://mi-proveedor.example.com'
      )

      service.send(:client)
    end

    it 'falls back to the OpenAI default when the hook has no base_url' do
      create_jabvox_ia_hook!

      expect(OpenAI::Client).to receive(:new).with(
        access_token: 'test-api-key', uri_base: 'https://api.openai.com/'
      )

      service.send(:client)
    end
  end
end
