# Auto-fills created_by_id with the acting user (Current.user) on create, for any
# Jabvox model that has a created_by_id column. One central place instead of
# touching dozens of controllers.
#
# - Only sets it when the column exists, it's still blank, and there's a Current
#   user in scope (web/API request). Background jobs / system writes leave it nil.
# - Never overrides an explicitly assigned created_by (e.g. controllers that set
#   it themselves, or an import that carries the original author).
module Jabvox::TracksCreator
  extend ActiveSupport::Concern

  included do
    # Association to read the creator's name (only if not already declared and the
    # column exists). optional: existing rows predate the tracking (nil creator).
    belongs_to :created_by, class_name: 'User', optional: true if column_names.include?('created_by_id') && !reflect_on_association(:created_by)
    before_create :assign_created_by_from_current
  end

  private

  def assign_created_by_from_current
    return unless self.class.column_names.include?('created_by_id')
    return if created_by_id.present?

    user = Current.user
    self.created_by_id = user.id if user.respond_to?(:id) && user.id.present?
  rescue StandardError => e
    # Never block a write over creator bookkeeping.
    Rails.logger.warn("[TracksCreator] #{self.class.name}: #{e.class}")
  end
end
