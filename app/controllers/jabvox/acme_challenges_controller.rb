module Jabvox
  class AcmeChallengesController < ApplicationController
    skip_before_action :verify_authenticity_token
    skip_before_action :authenticate_user!, raise: false
    skip_before_action :check_subscription, raise: false

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
