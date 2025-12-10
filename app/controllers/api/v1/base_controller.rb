module Api
  module V1
    class BaseController < ActionController::API
      # Error handling
      rescue_from ActiveRecord::RecordNotFound, with: :not_found
      rescue_from ArgumentError, with: :bad_request

      private

      def not_found(exception)
        render json: {
          error: "not_found",
          message: exception.message
        }, status: :not_found
      end

      def bad_request(exception)
        render json: {
          error: "bad_request",
          message: exception.message
        }, status: :bad_request
      end

      # Helper to validate year/number parameters
      def validate_regulation_params
        year = params[:year].to_i
        number = params[:number].to_i

        if year < 2000 || year > 2100
          raise ArgumentError, "Invalid year parameter"
        end

        if number < 1 || number > 999
          raise ArgumentError, "Invalid number parameter"
        end

        [ year, number ]
      end
    end
  end
end
