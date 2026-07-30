class AddExcludeOlderThanHoursToAssignmentPolicies < ActiveRecord::Migration[7.1]
  def change
    return if column_exists?(:assignment_policies, :exclude_older_than_hours)

    # Default 168 hours (7 days); nil disables the age exclusion for the policy
    add_column :assignment_policies, :exclude_older_than_hours, :integer, default: 168
  end
end
