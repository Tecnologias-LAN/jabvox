# frozen_string_literal: true

# CATÁLOGO DE NODOS: lo que el editor usa para pintar la paleta y los paneles de
# configuración. Es estático por cuenta, así que se cachea en el navegador.
class Api::V1::Accounts::Jabvox::Flows::NodesController < Api::V1::Accounts::Jabvox::Flows::BaseController
  def index
    render json: { 'nodes' => Jabvox::Flows::Catalog.all,
                   'enabledModules' => [], 'hiddenByModule' => [] }
  end
end
