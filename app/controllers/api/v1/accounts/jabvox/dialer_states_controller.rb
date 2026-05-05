# frozen_string_literal: true

class Api::V1::Accounts::Jabvox::DialerStatesController < Api::V1::Accounts::Jabvox::BaseController
  before_action :require_admin, only: %i[create update destroy]
  before_action :set_state, only: %i[update destroy]

  def index
    render json: Current.account.jabvox_dialer_states.ordered.map { |s| serialize(s) }
  end

  def create
    state = Current.account.jabvox_dialer_states.create!(state_params)
    render json: serialize(state), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def update
    @state.update!(state_params)
    render json: serialize(@state)
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @state.destroy!
    render json: { ok: true }
  end

  private

  def require_admin
    render json: { error: 'forbidden' }, status: :forbidden unless current_user.administrator?
  end

  def set_state
    @state = Current.account.jabvox_dialer_states.find(params[:id])
  end

  def state_params
    params.permit(:name, :color, :position, :is_active)
  end

  def serialize(state)
    { id: state.id, name: state.name, color: state.color, position: state.position, is_active: state.is_active }
  end
end
