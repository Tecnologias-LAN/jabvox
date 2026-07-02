class Api::V1::Accounts::Jabvox::AudioAnalysis::ReportsController < Api::V1::Accounts::Jabvox::AudioAnalysis::BaseController
  before_action :ensure_can_view_reports, except: [:my_access]

  # GET /access/my — used by the frontend guard and to gate the UI.
  # `can_manage` mirrors the backend `ensure_can_manage` gate (jabvox_audio_manage),
  # so the Pipelines/Storages tabs show for anyone who can actually manage them,
  # not only pure administrators.
  def my_access
    render json: {
      can_access: can_access?,
      can_view_reports: can_view_reports?,
      can_manage: jabvox_can?('jabvox_audio_manage'),
      is_admin: Current.account_user&.administrator? || false
    }
  end

  # GET /reports/daily — jobs grouped by day, each with its per-audio results,
  # plus an overall summary across the whole filtered range.
  def daily
    jobs = filtered_jobs.includes(:pipeline).recent
    results = filtered_results(jobs)
    results_by_job = results.group_by(&:job_id)
    grouped = jobs.group_by { |j| j.created_at.to_date.iso8601 }

    days = grouped.filter_map do |date, day_jobs|
      jobs_payload = day_jobs.filter_map do |j|
        rows = results_by_job[j.id] || []
        # When a score filter is active, drop jobs that ended up with no matching audios.
        next if score_filter_active? && rows.empty?

        job_summary(j).merge(results: rows.map { |r| result_payload(r) })
      end
      next if jobs_payload.empty?

      { date: date, jobs: jobs_payload, totals: aggregate_results(jobs_payload.flat_map { |j| j[:results] }) }
    end

    render json: { days: days, summary: overall_summary(results) }
  end

  # GET /reports/filter_options — pipelines + agents for the report filters.
  def filter_options
    render json: {
      pipelines: Current.account.jabvox_audio_pipelines.ordered.map { |p| { id: p.id, name: p.name } },
      agents: Current.account.users.select(:id, :name).map { |u| { id: u.id, name: u.name } }
    }
  end

  private

  def filtered_jobs
    scope = Current.account.jabvox_audio_jobs
    scope = scope.where('jabvox_audio_jobs.created_at >= ?', params[:from]) if params[:from].present?
    scope = scope.where('jabvox_audio_jobs.created_at <= ?', params[:to]) if params[:to].present?
    scope = scope.where(pipeline_id: params[:pipeline_id]) if params[:pipeline_id].present?
    scope = scope.where(created_by_id: params[:created_by_id]) if params[:created_by_id].present?
    # Search by analysis label (e.g. "analisis3"); case-insensitive partial match.
    if params[:label].present?
      scope = scope.where('label_jabvox ILIKE ?', "%#{params[:label].to_s.strip}%")
    end
    scope
  end

  # Per-audio results for the given jobs, with score / agent filters applied.
  def filtered_results(jobs)
    scope = JabvoxAudioResult.where(job_id: jobs.map(&:id)).includes(:assigned_agent, :typification)
    scope = scope.where(assigned_agent_id: params[:agent_id]) if params[:agent_id].present?
    if score_filter_active?
      value = params[:score_value].to_f
      scope = params[:score_op] == 'lt' ? scope.where('final_score < ?', value) : scope.where('final_score >= ?', value)
    end
    scope.to_a
  end

  def score_filter_active?
    params[:score_value].present? && params[:score_op].present?
  end

  def job_summary(job)
    {
      id: job.id, label: job.label_jabvox, status: job.status, pipeline: job.pipeline&.name,
      total_count: job.total_count, processed_count: job.processed_count,
      passed_count: job.passed_count, failed_count: job.failed_count,
      average_score: job.average_score,
      sentiment: { positive: job.positive_count, neutral: job.neutral_count, negative: job.negative_count }
    }
  end

  def result_payload(result)
    {
      id: result.id,
      file_key: result.file_key,
      status: result.status,
      transcript: result.transcript,
      transcript_words: result.transcript_words_jabvox,
      final_score: result.final_score,
      passed: result.passed,
      sentiment: result.sentiment,
      stages_data: result.stages_data,
      assigned_agent_name: result.assigned_agent&.name,
      typification_name: result.typification&.name
    }
  end

  # Aggregates computed from the actual (filtered) audios shown.
  def aggregate_results(rows)
    scored = rows.filter_map { |r| r[:final_score] }
    {
      total: rows.size,
      passed: rows.count { |r| r[:passed] },
      failed: rows.count { |r| r[:status] == 'completed' && !r[:passed] },
      positive: rows.count { |r| r[:sentiment] == 'positive' },
      neutral: rows.count { |r| r[:sentiment] == 'neutral' },
      negative: rows.count { |r| r[:sentiment] == 'negative' },
      average_score: scored.any? ? (scored.sum.to_f / scored.size).round(1) : nil
    }
  end

  # Overall summary across every filtered audio in the range.
  def overall_summary(results)
    scored = results.filter_map(&:final_score)
    {
      total: results.size,
      passed: results.count(&:passed),
      failed: results.count { |r| r.status == 'completed' && !r.passed },
      positive: results.count { |r| r.sentiment == 'positive' },
      neutral: results.count { |r| r.sentiment == 'neutral' },
      negative: results.count { |r| r.sentiment == 'negative' },
      average_score: scored.any? ? (scored.sum.to_f / scored.size).round(1) : nil
    }
  end
end
