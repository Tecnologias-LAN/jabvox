# Orchestrates the full sync-to-Meta lifecycle for a JabvoxWhatsappFlow (architecture
# doc section 5.4): validate locally -> compile to Flow JSON 7.3 -> create in Meta if
# needed -> upload JSON -> fetch validation status -> optionally publish -> persist a
# version snapshot and update local/remote status. Mirrors the error-handling style of
# Jabvox::WhatsappTemplatesManager ({ success:, error: } / { success:, flow: }).
class Jabvox::WhatsappFlows::PublishService
  def initialize(flow, user: nil)
    @flow = flow
    @user = user
  end

  # publish: false just validates + syncs the JSON to Meta as DRAFT (used by "Guardar"
  # in the builder). publish: true additionally calls Meta's /publish (used by the
  # explicit "Publicar" action) — irreversible on Meta's side once done.
  def call(publish: false)
    validation = Jabvox::WhatsappFlows::Validator.new(@flow).call
    @flow.update!(validation_errors_json: validation[:errors])
    return { success: false, error: 'El flow tiene errores de validación', errors: validation[:errors] } unless validation[:valid]

    @flow.update!(status: 'validating')
    flow_json = Jabvox::WhatsappFlows::JsonCompiler.new(@flow).call
    client = Jabvox::WhatsappFlows::MetaClient.new(@flow)

    ensure_result = ensure_created_in_meta(client)
    return fail_sync(ensure_result[:error]) unless ensure_result[:success]

    upload_result = client.update_json(flow_json)
    return fail_sync(upload_result[:error]) unless upload_result[:success]

    sync_result = client.fetch_status
    return fail_sync(sync_result[:error]) unless sync_result[:success]

    apply_meta_status(sync_result[:data])

    if publish
      publish_result = client.publish
      return fail_sync(publish_result[:error]) unless publish_result[:success]

      @flow.update!(status: 'published', published_at: Time.current)
    elsif @flow.status == 'validating'
      @flow.update!(status: 'ready')
    end

    save_version
    { success: true, flow: @flow }
  rescue StandardError => e
    Rails.logger.error "[WA Flows] PublishService failed for flow=#{@flow.id}: #{e.message}"
    fail_sync(e.message)
  end

  private

  def ensure_created_in_meta(client)
    return { success: true } if @flow.meta_flow_id.present?

    result = client.create
    @flow.update!(meta_flow_id: result[:meta_flow_id]) if result[:success]
    result
  end

  def apply_meta_status(data)
    return if data.blank?

    @flow.update!(
      meta_status: data['status'] || @flow.meta_status,
      meta_json: data,
      validation_errors_json: data['validation_errors'] || @flow.validation_errors_json
    )
  end

  def fail_sync(error)
    @flow.update!(status: 'sync_failed')
    { success: false, error: error }
  end

  def save_version
    next_ver = (@flow.versions.maximum(:version) || 0) + 1
    @flow.versions.create!(version: next_ver, screens_json: @flow.screens_json, created_by: @user)
  end
end
