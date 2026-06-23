require 'aws-sdk-s3'

# S3/MinIO access for the Audio Analysis module. A storage can either carry its
# own credentials or reuse the AI-chat (Documentos) bucket config.
class Jabvox::AudioBucketService
  AUDIO_EXTENSIONS = %w[.mp3 .m4a .wav .ogg .opus .flac .webm].freeze

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

  def list_objects(prefix: '')
    full_prefix = [@creds[:path_prefix], prefix].reject(&:blank?).join
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
        files << { key: o.key, size: o.size, last_modified: o.last_modified } if audio?(o.key)
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
