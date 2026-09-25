# frozen_string_literal: true

# Representación pública de una fuente de datos: NUNCA incluye password ni ssl_ca.
#
# La lista de atributos es una allowlist a propósito, no una exclusión: así, añadir una
# columna con un secreto al modelo no la filtra por olvido: hay que nombrarla aquí para que
# salga.
class Jabvox::Analytics::DataSourceSerializer
  ATTRS = %i[
    id name_jabvox engine_jabvox host_jabvox port_jabvox database_jabvox username_jabvox
    sqlite_path_jabvox ssl_mode_jabvox allow_private_network_jabvox max_rows_jabvox
    query_timeout_ms_jabvox status_jabvox last_tested_at_jabvox created_at
  ].freeze

  def initialize(source)
    @source = source
  end

  # La contraseña no viaja; solo si la hay, para que el formulario sepa si dejar el campo
  # vacío significa "no cambiarla".
  def call
    @source.slice(*ATTRS).symbolize_keys.merge(has_password: @source.password_jabvox.present?)
  end
end
