# frozen_string_literal: true

# Modo "solo Hermes" (sin ContextForge): la cuenta se conecta directo a un Hermes que se
# auto-aprovisiona contra Jabvox. Solo hace falta la URL del Hermes de la cuenta.
class AddHermesUrlToContextForgeHandoffs < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_context_forge_handoffs, :hermes_url, :string
  end
end
