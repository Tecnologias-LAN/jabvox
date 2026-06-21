module Enterprise::Concerns::AssignmentPolicy
  extend ActiveSupport::Concern

  included do
    enum assignment_order: { round_robin: 0, balanced: 1 } if JabvoxApp.enterprise?
  end
end
