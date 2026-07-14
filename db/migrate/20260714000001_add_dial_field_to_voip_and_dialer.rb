# Lets an account choose WHICH number field gets dialed, plus a country prefix
# for fields that store the number without one.
#
# voip_config (click-to-call): dial_field_jabvox names the field to dial —
#   'phone' (the contact's phone_number, the default when blank) or a custom
#   column key (e.g. 'movil_2_c'). dial_prefix_jabvox is prepended to numbers
#   that don't already carry a country code.
#
# dialer_campaign: same two fields, but the campaign form makes dial_field
#   REQUIRED (one field per campaign). A blank value still falls back to 'phone'
#   for safety.
class AddDialFieldToVoipAndDialer < ActiveRecord::Migration[7.1]
  def change
    add_column :jabvox_voip_configs, :dial_field_jabvox, :string
    add_column :jabvox_voip_configs, :dial_prefix_jabvox, :string

    add_column :jabvox_dialer_campaigns, :dial_field_jabvox, :string
    add_column :jabvox_dialer_campaigns, :dial_prefix_jabvox, :string
  end
end
