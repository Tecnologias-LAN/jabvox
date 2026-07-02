# Exposes a virtual `jabvox_modules` reader so the Super Admin account
# dashboard can render every per-account Jabvox module toggle as one grouped
# field (a grid of tiles) instead of ~25 separate boolean rows.
#
# Administrate resolves a field's value via `resource.public_send(attribute)`,
# so this attribute must exist even though it is not a real column. The value
# itself is unused by JabvoxModulesField (which reads the account columns
# directly); returning self keeps the resolver happy and gives the field a
# handle to the account.
module Jabvox::AccountModulesAdmin
  extend ActiveSupport::Concern

  def jabvox_modules
    self
  end
end
