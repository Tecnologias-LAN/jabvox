# frozen_string_literal: true

# Periodo de facturación del plan (mensual/anual), para claridad en el panel y en el
# recordatorio de renovación. La duración real en días sigue viviendo en duration_days.
class AddBillingPeriodToJabvoxPlans < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_plans, :billing_period, :integer, null: false, default: 0
  end
end
