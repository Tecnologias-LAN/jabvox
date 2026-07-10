class AddFiltersAndPhonePrefixToJabvoxLeadSources < ActiveRecord::Migration[7.1]
  def change
    change_table :jabvox_lead_sources, bulk: true do |t|
      # Row filters applied to the sync SELECT: [{column, op, value, value2}]
      t.jsonb :filters_jabvox, default: [], null: false
      # Default country calling code (e.g. "57") used to normalize phones to E.164.
      t.string :phone_prefix_jabvox, default: '', null: false
    end
  end
end
