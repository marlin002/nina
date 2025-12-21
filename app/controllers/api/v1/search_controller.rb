module Api
  module V1
    class SearchController < BaseController
      # GET /api/v1/search?q=arbetsgivaren
      # Search across all regulations and return API references
      def index
        query = params[:q].to_s.strip

        if query.blank?
          render json: { error: "bad_request", message: "Query parameter 'q' is required" }, status: :bad_request
          return
        end

        if query.length > 100
          render json: { error: "bad_request", message: "Query too long (max 100 characters)" }, status: :bad_request
          return
        end

        # Use ElementSearchService to find matching elements
        search_service = ElementSearchService.new(limit: AppConstants::MAX_SEARCH_RESULTS)
        elements = search_service.search(query)

        # Build unique API references from elements
        references = build_references(elements)

        render json: {
          query: query,
          references: references
        }
      end

      private

      # Build API reference paths from elements
      def build_references(elements)
        references = []
        seen = Set.new

        elements.each do |element|
          ref = build_reference_path(element)
          next if ref.nil? || seen.include?(ref)
          
          seen.add(ref)
          references << ref
        end

        references
      end

      # Build API reference path for a single element
      def build_reference_path(element)
        # Parse regulation to extract year and number
        regulation_match = element.regulation.match(/AFS (\d{4}):(\d+)/)
        return nil unless regulation_match

        year = regulation_match[1]
        number = regulation_match[2]

        # Appendices
        if element.appendix.present?
          return "/api/v1/regulations/#{year}/#{number}/appendices/#{element.appendix}"
        end

        # Sections
        if element.section.present?
          if element.chapter.present?
            return "/api/v1/regulations/#{year}/#{number}/chapters/#{element.chapter}/sections/#{element.section}"
          else
            return "/api/v1/regulations/#{year}/#{number}/sections/#{element.section}"
          end
        end

        # Skip elements that don't belong to sections or appendices (e.g., preambles)
        nil
      end
    end
  end
end
