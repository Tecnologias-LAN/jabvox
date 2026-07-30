# Raised when Meta's WhatsApp Groups API returns a non-2xx response. Carries the
# HTTP status so controllers can map it to a sensible response code.
class Jabvox::Whatsapp::GroupApiError < StandardError
  attr_reader :status

  def initialize(message, status = nil)
    @status = status
    super(message)
  end
end
