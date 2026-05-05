# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::AppStatesController < Api::V1::Accounts::BaseController
  before_action :require_admin, only: %i[create update destroy]
  before_action :set_app_state, only: %i[update destroy]

  def index
    states = Current.account.jabvox_app_states.ordered.map { |s| serialize(s) }
    render json: { states: states, current_user_state_id: Current.account_user&.jabvox_app_state_id }
  end

  def create
    state = Current.account.jabvox_app_states.create!(app_state_params)
    render json: serialize(state), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @app_state.update!(app_state_params)
    render json: serialize(@app_state)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @app_state.destroy!
    render json: { ok: true }
  end

  def set_presence
    au = AccountUser.find_by!(account: Current.account, user: current_user)
    now = Time.current
    new_state_id = params[:app_state_id].presence

    JabvoxAppStateLog.where(account_id: Current.account.id, user_id: current_user.id, ended_at: nil)
                     .update_all(ended_at: now)
    JabvoxAppStateLog.create!(account_id: Current.account.id, user_id: current_user.id,
                              app_state_id: new_state_id, started_at: now)

    au.update!(jabvox_app_state_id: new_state_id, jabvox_app_state_changed_at: now)
    ActionCable.server.broadcast("account_#{Current.account.id}",
                                  { event: 'jabvox.agent_state_changed', data: { account_id: Current.account.id } })
    render json: { ok: true }
  end

  private

  def require_admin
    render json: { error: 'forbidden' }, status: :forbidden unless current_user.administrator?
  end

  def set_app_state
    @app_state = Current.account.jabvox_app_states.find(params[:id])
  end

  def app_state_params
    params.permit(:name, :color, :position, :is_active)
  end

  def serialize(state)
    { id: state.id, name: state.name, color: state.color, position: state.position, is_active: state.is_active }
  end
end
