# frozen_string_literal: true

# Conecta un Hermes/ContextForge YA EXISTENTE a una cuenta, sin aprovisionar desde cero.
# Recibe los datos del handoff (base_url, virtual server, scoped token), valida que el
# token funcione listando tools, y persiste el handoff en estado ready.
class ContextForge::ConnectExistingService
  Result = Struct.new(:success, :handoff, :error, keyword_init: true) do
    def success? = success
  end

  def initialize(account, attrs = {})
    @account = account
    @base_url = attrs[:base_url].to_s.strip
    @virtual_server_id = attrs[:virtual_server_id].to_s.strip
    @scoped_token = attrs[:scoped_token].to_s.strip
    @team_id = attrs[:team_id]
    @hermes_instance_id = attrs[:hermes_instance_id]
    @service = attrs[:service] || ContextForge::Service.new
  end

  def call
    missing = required_missing
    return failure("Faltan datos: #{missing.join(', ')}") if missing.any?

    check = @service.list_tools(@scoped_token, base_url: @base_url)
    return failure("El token no validó contra ContextForge: #{check.error}") unless check.success?

    handoff = persist(check.data)
    Result.new(success: true, handoff: handoff)
  rescue StandardError => e
    failure(e.message)
  end

  private

  def required_missing
    { 'base_url' => @base_url, 'virtual_server_id' => @virtual_server_id,
      'scoped_token' => @scoped_token }.select { |_k, v| v.blank? }.keys
  end

  def persist(tools)
    handoff = JabvoxContextForgeHandoff.find_or_create_by!(account_id: @account.id)
    handoff.mark_ready!(
      contextforge_base_url: @base_url,
      virtual_server_id: @virtual_server_id,
      team_id: @team_id,
      hermes_instance_id: @hermes_instance_id,
      scoped_token: @scoped_token,
      mcp_servers: Array(tools).map { |t| { 'name' => t.to_s } }
    )
    handoff
  end

  def failure(msg)
    Result.new(success: false, error: msg)
  end
end
