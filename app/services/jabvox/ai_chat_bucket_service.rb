module Jabvox
  class AiChatBucketService
    def initialize(config)
      @config = config
    end

    def list_objects(prefix: '')
      client.list_objects_v2(bucket: bucket_name, prefix: prefix).contents.map do |obj|
        { key: obj.key, size: obj.size, last_modified: obj.last_modified, content_type: nil }
      end
    rescue Aws::S3::Errors::ServiceError => e
      raise "Error al listar el bucket: #{e.message}"
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

    def object_exists?(s3_key)
      client.head_object(bucket: bucket_name, key: s3_key)
      true
    rescue Aws::S3::Errors::NotFound
      false
    end

    private

    def client
      options = {
        region: @config.bucket_region_jabvox.presence || 'us-east-1',
        access_key_id: @config.bucket_access_key_jabvox,
        secret_access_key: @config.bucket_secret_key_jabvox,
        endpoint: custom_endpoint,
        force_path_style: custom_endpoint.present?
      }
      options[:ssl_verify_peer] = false if custom_endpoint.present?
      @client ||= Aws::S3::Client.new(**options)
    end

    def custom_endpoint
      @config.bucket_url_jabvox.presence
    end

    def bucket_name
      @config.bucket_name_jabvox
    end
  end
end
