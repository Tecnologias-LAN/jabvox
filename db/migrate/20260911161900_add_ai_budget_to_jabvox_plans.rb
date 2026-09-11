# frozen_string_literal: true

# Saldo mensual de IA que otorga el plan (en centavos de USD). Este saldo se RESTABLECE
# cada mes por el worker mensual; lo que la cuenta compra aparte se acumula por separado.
# 0 = el plan no incluye saldo de IA.
class AddAiBudgetToJabvoxPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_plans, :ai_budget_cents_jabvox, :integer, null: false, default: 0
  end
end
