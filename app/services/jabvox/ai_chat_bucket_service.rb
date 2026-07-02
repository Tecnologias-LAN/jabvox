module Jabvox
  class AiChatBucketService
    PAGE_SIZE = 1000
    MAX_PAGES = 50

    def initialize(config)
      @config = config
    end

    # Lists every object in the bucket (folders collapsed to their file keys).
    # `search` is an optional case-insensitive substring filter on the file name
    # so the document picker can narrow a large bucket without paginating S3.
    # Validates the bucket credentials without saving. Returns a sanitized result.
    def test_connection
      return { success: false, message: 'Bucket no configurado.' } unless configured?

      client.list_objects_v2(bucket: bucket_name, max_keys: 1)
      { success: true, message: 'Conexión con el bucket establecida.' }
    rescue Aws::S3::Errors::ServiceError, StandardError => e
      { success: false, message: e.message }
    end

    # Flat, recursive listing of every file in the bucket (folders collapsed).
    # Used by callers that want the whole set at once (e.g. response bot sync).
    def list_objects(prefix: '', search: '')
      needle = search.to_s.strip.downcase
      objects = []
      continuation = nil

      loop do
        page = client.list_objects_v2(
          bucket: bucket_name, prefix: prefix, continuation_token: continuation
        )
        objects.concat(matching_objects(page.contents, needle))
        break unless page.is_truncated

        continuation = page.next_continuation_token
      end

      objects
    rescue Aws::S3::Errors::ServiceError => e
      raise "Error al listar el bucket: #{e.message}"
    end

    # Folder-aware listing for the document picker: returns the subfolders and
    # files directly under `prefix` (using S3's '/' delimiter), so the UI can
    # navigate in and out of folders — same behavior as Audio Analysis.
    # `search` filters files by a case-insensitive substring of the file name;
    # folders are always shown.
    def browse(prefix: '', search: '')
      needle = search.to_s.strip.downcase
      folders = []
      files = []
      token = nil
      truncated = false

      MAX_PAGES.times do |page|
        resp = client.list_objects_v2(
          bucket: bucket_name, prefix: prefix, max_keys: PAGE_SIZE,
          continuation_token: token, delimiter: '/'
        )
        folders.concat(resp.common_prefixes.map(&:prefix))
        files.concat(matching_objects(resp.contents, needle))
        token = resp.next_continuation_token
        break unless token

        truncated = true if page == MAX_PAGES - 1
      end

      { folders: folders, files: files, total_folders: folders.size, total_files: files.size, truncated: truncated }
    rescue Aws::S3::Errors::ServiceError => e
      { folders: [], files: [], total_folders: 0, total_files: 0, truncated: false, error: e.message }
    end

    def read_document(s3_key)
      resp = client.get_object(bucket: bucket_name, key: s3_key)
      body = resp.body.read

      if resp.content_type&.include?('text')
        body.force_encoding('UTF-8').encode('UTF-8', invalid: :replace, undef: :replace)
      else
        body.encode('UTF-8', invalid: :replace, undef: :replace) rescue nil
      end
    rescue Aws::S3::Errors::ServiceError
      nil
    end

    def public_url(s3_key)
      "#{custom_endpoint.to_s.chomp('/')}/#{bucket_name}/#{s3_key}"
    end

    def object_exists?(s3_key)
      client.head_object(bucket: bucket_name, key: s3_key)
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    # A bucket is usable only once it has endpoint, bucket name AND credentials
    # (access + secret). Checking the secret here turns the cryptic AWS
    # "unable to sign request without credentials set" into a clear, actionable
    # error before any S3 call. Works for either credential source.
    def configured?
      @config.present? &&
        custom_endpoint.present? && bucket_name.present? &&
        access_key.present? && secret_key.present?
    end

    private

    # Filters a page of S3 objects: drops folder placeholders and, when a search
    # term is given, keeps only files whose name contains it (case-insensitive).
    def matching_objects(contents, needle)
      contents.filter_map do |obj|
        next if obj.key.end_with?('/')
        next if needle.present? && File.basename(obj.key).downcase.exclude?(needle)

        { key: obj.key, size: obj.size, last_modified: obj.last_modified, content_type: nil }
      end
    end

    def client
      options = {
        region: bucket_region,
        access_key_id: access_key,
        secret_access_key: secret_key,
        endpoint: custom_endpoint,
        force_path_style: custom_endpoint.present?
      }
      options[:ssl_verify_peer] = false if custom_endpoint.present?
      @client ||= Aws::S3::Client.new(**options)
    end

    # Bucket credentials are read uniformly from either source so AI Chat can
    # target its own inline config (`JabvoxAiChatConfig`, `*_jabvox` columns) or
    # a shared storage (`JabvoxAudioStorage`, plain columns). The presence of
    # `bucket_name_jabvox` distinguishes the two.
    def ai_chat_config?
      @config.respond_to?(:bucket_name_jabvox)
    end

    def custom_endpoint
      (ai_chat_config? ? @config.bucket_url_jabvox : @config.endpoint).presence
    end

    def bucket_name
      ai_chat_config? ? @config.bucket_name_jabvox : @config.bucket_name
    end

    def bucket_region
      region = ai_chat_config? ? @config.bucket_region_jabvox : @config.bucket_region
      region.presence || 'us-east-1'
    end

    def access_key
      ai_chat_config? ? @config.bucket_access_key_jabvox : @config.access_key
    end

    def secret_key
      ai_chat_config? ? @config.bucket_secret_key_jabvox : @config.secret_key
    end
  end
end
