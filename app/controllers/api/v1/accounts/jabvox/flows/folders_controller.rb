# frozen_string_literal: true

# Carpetas para organizar los flujos de la cuenta.
class Api::V1::Accounts::Jabvox::Flows::FoldersController < Api::V1::Accounts::Jabvox::Flows::BaseController
  before_action :set_folder, only: [:update, :destroy]

  def index
    render json: folders_scope.includes(:flows).order(:name).map { |f| Jabvox::Flows::Serializer.folder(f) }
  end

  def create
    folder = folders_scope.new(name: params[:name])
    return render_error(folder.errors.full_messages.to_sentence) unless folder.save

    render json: Jabvox::Flows::Serializer.folder(folder), status: :created
  end

  def update
    return render_error(@folder.errors.full_messages.to_sentence) unless @folder.update(name: params[:name])

    render json: Jabvox::Flows::Serializer.folder(@folder)
  end

  # Borrar la carpeta NUNCA borra flujos: `dependent: :nullify` los deja sueltos
  # en la raíz. Se responde con cuántos se movieron, para poder avisar.
  def destroy
    moved = @folder.flows.count
    @folder.destroy!
    render json: { 'movedToRoot' => moved }
  end

  private

  def folders_scope
    Current.account.jabvox_flow_folders
  end

  def set_folder
    @folder = folders_scope.find(params[:id])
  end
end
