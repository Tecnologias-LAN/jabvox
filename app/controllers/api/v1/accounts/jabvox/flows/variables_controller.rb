# frozen_string_literal: true

# Variables GLOBALES de cuenta (`{{global.<clave>}}`). El valor de una variable
# secreta nunca sale al navegador.
class Api::V1::Accounts::Jabvox::Flows::VariablesController < Api::V1::Accounts::Jabvox::Flows::BaseController
  before_action :set_variable, only: [:update, :destroy]

  def index
    render json: variables_scope.order(:key).map { |v| Jabvox::Flows::Serializer.variable(v) }
  end

  def create
    variable = variables_scope.new(variable_params)
    return render_error(variable.errors.full_messages.to_sentence) unless variable.save

    render json: Jabvox::Flows::Serializer.variable(variable), status: :created
  end

  # Sin `value` en la petición el valor se conserva: así el editor puede
  # renombrar o describir una variable secreta sin conocer su contenido.
  def update
    attrs = variable_params
    attrs = attrs.except(:value) unless params.key?(:value)
    return render_error(@variable.errors.full_messages.to_sentence) unless @variable.update(attrs)

    render json: Jabvox::Flows::Serializer.variable(@variable)
  end

  def destroy
    @variable.destroy!
    head :no_content
  end

  private

  def variables_scope
    Current.account.jabvox_flow_account_variables
  end

  def set_variable
    @variable = variables_scope.find(params[:id])
  end

  def variable_params
    params.permit(:key, :value, :description, :secret).to_h.symbolize_keys
  end
end
