class ClearDialerCallingHoursDefaults < ActiveRecord::Migration[7.1]
  # Empty calling hours must mean "any time", not "08:00-18:00". The column
  # defaults forced every campaign into a 8am-6pm window even when the user
  # left them blank. Drop the defaults so blank = no restriction.
  def up
    change_column_default :jabvox_dialer_campaigns, :calling_hours_start_jabvox, from: '08:00', to: nil
    change_column_default :jabvox_dialer_campaigns, :calling_hours_end_jabvox, from: '18:00', to: nil
  end

  def down
    change_column_default :jabvox_dialer_campaigns, :calling_hours_start_jabvox, from: nil, to: '08:00'
    change_column_default :jabvox_dialer_campaigns, :calling_hours_end_jabvox, from: nil, to: '18:00'
  end
end
