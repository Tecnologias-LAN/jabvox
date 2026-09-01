# frozen_string_literal: true

module Jabvox
  module Reports
    # Raised when a requested report range exceeds TimeRange::MAX_RANGE_DAYS.
    # The controller rescues this into a 422 (section 5: hard limits).
    class RangeTooLargeError < StandardError; end
  end
end
