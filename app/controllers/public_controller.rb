# TODO: we should switch to ActionController::API for the base classes
# One of the specs is failing when I tried doing that, lets revisit in future
#
# Los metodos `ensure_custom_domain_request` y `ensure_portal_feature_enabled` vivian aqui
# para los portales del centro de ayuda, que se retiro del producto. La clase sigue siendo
# la base de los controladores publicos que si se usan (CSAT, widget de bandejas).
class PublicController < ActionController::Base
  include RequestExceptionHandler
  skip_before_action :verify_authenticity_token
end
