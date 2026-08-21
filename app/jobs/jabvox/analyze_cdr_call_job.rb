class Jabvox::AnalyzeCdrCallJob < ApplicationJob
  queue_as :jabvox_cdr

  def perform(account_id, uniqueid, pipeline_id: nil, force: false)
    account = Account.find_by(id: account_id)
    return unless account
    return unless account.feature_enabled?('jabvox_cdr')

    pipeline = account.jabvox_cdr_pipelines.find_by(id: pipeline_id) if pipeline_id
    Jabvox::CdrAnalysisService.new(account: account, uniqueid: uniqueid, pipeline: pipeline, force: force).call
  end
end
