module Jabvox
  class AcmeChallengesController < ActionController::Base
    def show
      content = Rails.cache.read("jabvox_acme_#{params[:token]}")
      if content
        render plain: content, content_type: 'text/plain'
      else
        head :not_found
      end
    end
  end
end
