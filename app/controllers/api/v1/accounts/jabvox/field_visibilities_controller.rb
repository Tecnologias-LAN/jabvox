module Api::V1::Accounts::Jabvox
  class FieldVisibilitiesController < Api::V1::Accounts::BaseController
    before_action :check_admin!, except: [:me]

    # GET /api/v1/accounts/:account_id/jabvox/field_visibilities
    def index
      users = Current.account.users.order(:name)
      visibilities_by_key = Current.account.jabvox_field_visibilities
                                           .index_by { |v| [v.user_id, v.field_name] }

      render json: users.map { |user| user_row(user, visibilities_by_key) }
    end

    # GET /api/v1/accounts/:account_id/jabvox/field_visibilities/me
    def me
      visibilities = Current.account.jabvox_field_visibilities
                                    .where(user_id: current_user.id)
                                    .index_by(&:field_name)

      render json: JabvoxFieldVisibility::FIELDS.index_with do |field|
        visibilities[field] ? visibilities[field].can_view : true
      end
    end

    # PATCH /api/v1/accounts/:account_id/jabvox/field_visibilities
    def update
      visibility = Current.account.jabvox_field_visibilities.find_or_initialize_by(
        user_id: params[:user_id],
        field_name: params[:field_name]
      )
      visibility.can_view = params[:can_view]
      visibility.save!
      render json: { success: true }
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    private

    def user_row(user, visibilities_by_key)
      {
        id: user.id,
        name: user.name,
        email: user.email,
        visibilities: JabvoxFieldVisibility::FIELDS.index_with do |field|
          vis = visibilities_by_key[[user.id, field]]
          vis ? vis.can_view : true
        end
      }
    end

    def check_admin!
      return if current_user.administrator?

      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end
end
