require 'aws-sdk-s3'

# S3/MinIO access for the Audio Analysis module. A storage can either carry its
# own credentials or reuse the AI-chat (Documentos) bucket config.
class Jabvox::AudioBucketService
  AUDIO_EXTENSIONS = %w[.mp3 .m4a .wav .ogg .opus .flac .webm].freeze
  DOCUMENT_EXTENSIONS = %w[.pdf .doc .docx .xls .xlsx .csv .txt .ppt .pptx
                           .png .jpg .jpeg .gif .webp .zip].freeze
  LISTABLE_EXTENSIONS = (AUDIO_EXTENSIONS + DOCUMENT_EXTENSIONS).freeze

  def initialize(storage)
    @storage = storage
    @creds = resolve_credentials
  end

  def test_connection
    client.list_objects_v2(bucket: bucket_name, max_keys: 1)
    { success: true, message: 'Conexión con el bucket establecida.' }
  rescue Aws::S3::Errors::ServiceError, StandardError => e
    { success: false, message: e.message }
  end

  # Lists EVERY object under a prefix (audio files only) plus subfolders, walking
  # S3's continuation_token until exhausted. The frontend paginates the result.
  # A page count cap guards against pathological prefixes (very large buckets).
  PAGE_SIZE = 1000
  MAX_PAGES = 50

  # `search` filters listed files by a case-insensitive substring of the file name
  # (e.g. "1000532535_" matches 1000532535_1, _2, …). Folders are always shown.
  def list_objects(prefix: '', search: '')
    full_prefix = [@creds[:path_prefix], prefix].reject(&:blank?).join
    needle = search.to_s.strip.downcase
    folders = []
    files = []
    token = nil
    truncated = false

    MAX_PAGES.times do |page|
      resp = client.list_objects_v2(
        bucket: bucket_name, prefix: full_prefix, max_keys: PAGE_SIZE,
        continuation_token: token, delimiter: '/'
      )
      folders.concat(resp.common_prefixes.map(&:prefix))
      resp.contents.each do |o|
        next unless listable?(o.key)
        next if needle.present? && !File.basename(o.key).downcase.include?(needle)

        files << { key: o.key, size: o.size, last_modified: o.last_modified, kind: kind_for(o.key) }
      end
      token = resp.next_continuation_token
      break unless token

      truncated = true if page == MAX_PAGES - 1
    end

    {
      folders: folders,
      files: files,
      total_folders: folders.size,
      total_files: files.size,
      truncated: truncated
    }
  rescue Aws::S3::Errors::ServiceError, StandardError => e
    Rails.logger.error "[AudioAnalysis] list failed: #{e.message}"
    { folders: [], files: [], total_folders: 0, total_files: 0, truncated: false, error: e.message }
  end

  # Short-lived presigned URL to stream/play a file directly from the bucket in
  # the browser. Expires fast (5 min) to limit the leak window. The key is
  # validated against this storage's allowed prefix and listable extensions, so a
  # client cannot presign arbitrary objects (path traversal / out-of-scope keys).
  def presigned_url(file_key, expires_in: 300)
    return nil unless allowed_key?(file_key)

    signer = Aws::S3::Presigner.new(client: client)
    signer.presigned_url(:get_object, bucket: bucket_name, key: file_key, expires_in: expires_in)
  rescue Aws::S3::Errors::ServiceError, StandardError => e
    Rails.logger.error "[AudioAnalysis] presign failed: #{e.message}"
    nil
  end

  # A key is allowed only if it is a normalized path under this storage's
  # path_prefix and has a listable extension. Blocks "..", absolute keys, and
  # keys pointing outside the configured prefix.
  def allowed_key?(file_key)
    key = file_key.to_s
    return false if key.blank? || key.include?('..') || key.start_with?('/')
    return false unless listable?(key)

    prefix = @creds[:path_prefix].to_s
    prefix.blank? || key.start_with?(prefix)
  end

  # Downloads a file to a Tempfile (binmode). Caller must close! it.
  def download(file_key)
    tmp = Tempfile.new(['audio', File.extname(file_key).presence || '.mp3'], binmode: true)
    client.get_object(bucket: bucket_name, key: file_key, response_target: tmp.path)
    tmp.rewind
    tmp
  rescue Aws::S3::Errors::ServiceError, StandardError => e
    Rails.logger.error "[AudioAnalysis] download failed: #{e.message}"
    tmp&.close!
    nil
  end

  private

  def audio?(key)
    AUDIO_EXTENSIONS.include?(File.extname(key).downcase)
  end

  def listable?(key)
    LISTABLE_EXTENSIONS.include?(File.extname(key).downcase)
  end

  # 'audio' for audio files, 'document' for everything else listable.
  def kind_for(key)
    audio?(key) ? 'audio' : 'document'
  end

  def resolve_credentials
    if @storage.use_documents_config?
      cfg = @storage.account.jabvox_ai_chat_config
      raise 'No hay configuración de Documentos disponible' unless cfg

      {
        bucket: cfg.bucket_name_jabvox, region: cfg.bucket_region_jabvox,
        endpoint: cfg.bucket_url_jabvox, access_key: cfg.bucket_access_key_jabvox,
        secret_key: cfg.bucket_secret_key_jabvox, path_prefix: @storage.path_prefix.to_s
      }
    else
      {
        bucket: @storage.bucket_name, region: @storage.bucket_region,
        endpoint: @storage.endpoint, access_key: @storage.access_key,
        secret_key: @storage.secret_key, path_prefix: @storage.path_prefix.to_s
      }
    end
  end

  def bucket_name
    @creds[:bucket]
  end

  def client
    options = {
      region: @creds[:region].presence || 'us-east-1',
      access_key_id: @creds[:access_key],
      secret_access_key: @creds[:secret_key]
    }
    endpoint = @creds[:endpoint].presence
    if endpoint
      options[:endpoint] = endpoint
      options[:force_path_style] = true
      options[:ssl_verify_peer] = false
    end
    @client ||= Aws::S3::Client.new(**options)
  end
end
