class Api::V1::Accounts::Jabvox::Cdr::ConfigsController < Api::V1::Accounts::Jabvox::Cdr::BaseController
  before_action :ensure_admin

  def show
    @config = Current.account.jabvox_cdr_config || JabvoxCdrConfig.new
    render json: serialize(@config)
  end

  def update
    @config = Current.account.jabvox_cdr_config || Current.account.build_jabvox_cdr_config
    # Keep existing secrets when the client sends them blank (not re-entered).
    @config.update!(config_params.except(*blank_secret_keys))
    render json: serialize(@config)
  end

  # POST /test — validate the MySQL credentials without saving them.
  def test
    config = Current.account.jabvox_cdr_config || JabvoxCdrConfig.new
    config.assign_attributes(config_params.except(*blank_secret_keys))
    render json: Jabvox::CdrMysqlService.new(config).test_connection
  end

  # POST /test_ssh — validate the SSH/SFTP credentials without saving them.
  def test_ssh
    config = Current.account.jabvox_cdr_config || JabvoxCdrConfig.new
    config.assign_attributes(config_params.except(*blank_secret_keys))
    render json: Jabvox::CdrRecordingService.new(config).test_connection
  end

  private

  def blank_secret_keys
    keys = []
    keys << :mysql_password if params.dig(:config, :mysql_password).blank?
    keys << :ssh_password if params.dig(:config, :ssh_password).blank?
    keys
  end

  def config_params
    params.require(:config).permit(
      :mysql_host, :mysql_port, :mysql_username, :mysql_password, :mysql_database, :mysql_table,
      :ssh_host, :ssh_port, :ssh_username, :ssh_password, :recordings_path,
      :analysis_mode, :min_duration_seconds, :default_pipeline_id
    )
  end

  def serialize(config)
    {
      mysql_host: config.mysql_host,
      mysql_port: config.mysql_port,
      mysql_username: config.mysql_username,
      mysql_database: config.mysql_database,
      mysql_table: config.mysql_table,
      mysql_password_set: config.mysql_password.present?,
      ssh_host: config.ssh_host,
      ssh_port: config.ssh_port,
      ssh_username: config.ssh_username,
      ssh_password_set: config.ssh_password.present?,
      recordings_path: config.recordings_path,
      analysis_mode: config.analysis_mode,
      min_duration_seconds: config.min_duration_seconds,
      default_pipeline_id: config.default_pipeline_id
    }
  end
end
