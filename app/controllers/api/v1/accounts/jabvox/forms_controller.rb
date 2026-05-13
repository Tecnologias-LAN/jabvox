class Api::V1::Accounts::Jabvox::FormsController < Api::V1::Accounts::BaseController
  before_action :check_authorization
  before_action :check_feature_enabled
  before_action :set_form, only: [:show, :update, :destroy]

  def index
    @forms = Current.account.jabvox_forms.ordered
  end

  def show; end

  def create
    @form = Current.account.jabvox_forms.new(form_params)
    @form.save!
    render :show, status: :created
  end

  def update
    @form.update!(form_params)
    render :show
  end

  def destroy
    @form.destroy!
    head :no_content
  end

  private

  def check_authorization(*)
    authorize(JabvoxForm)
  end

  def check_feature_enabled
    return if Current.account.feature_enabled?('jabvox_forms')

    render json: { error: 'Jabvox Forms feature is not enabled for this account' }, status: :forbidden
  end

  def set_form
    @form = Current.account.jabvox_forms.find(params[:id])
  end

  def form_params
    params.require(:form).permit(
      :name_jabvox, :slug_jabvox, :submit_button_text_jabvox, :active_jabvox,
      header_jabvox: [:html, :body_html, :bg_color, :button_color, :image_url, :layout, :title, :description],
      footer_jabvox: [:whatsapp, :facebook, :instagram, :website, :copyright],
      fields_jabvox: [:id, :type, :label, :required, { options: [] }],
      submit_actions_jabvox: [
        email:   [:enabled, :template_id],
        webhook: [:enabled, :url, :secret],
        success: [:message, :button_label, :button_url],
        privacy: [:enabled, :title, :body, :link_text, :link_url, :accept_text]
      ]
    )
  end
end
