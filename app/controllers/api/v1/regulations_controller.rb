module Api
  module V1
    class RegulationsController < BaseController
      # GET /api/v1/regulations
      # List all available regulations
      def index
        regulations = Scrape.current
          .joins(:source)
          .includes(:source)
          .map do |scrape|
            code = Regulations::Code.from_url(scrape.source.url)
            parsed = Regulations::Code.parse(code)
            
            {
              code: code,
              year: parsed[:year],
              number: parsed[:number],
              title: scrape.title
            }
          end
          .compact
          .sort_by { |r| [r[:year], r[:number]] }

        render json: regulations
      end

      # GET /api/v1/regulations/:year/:number/structure
      # Get structure of a regulation (chapters, sections, appendices)
      def structure
        year, number = validate_regulation_params
        
        structure = RegulationStructureService.structure(year: year, number: number)
        
        # Check if regulation exists
        if structure[:chapters].empty? && structure[:sections_without_chapter].empty? && structure[:appendices].empty?
          raise ActiveRecord::RecordNotFound, "Regulation not found: AFS #{year}:#{number}"
        end

        render json: structure
      end

      # GET /api/v1/regulations/:year/:number/sections/:section
      # Get a section without chapter (for regulations without chapters)
      def section_without_chapter
        year, number = validate_regulation_params
        section = params[:section].to_i

        raise ArgumentError, "Invalid section parameter" if section < 1

        content = RegulationContentBuilder.section_content(
          year: year,
          number: number,
          chapter: nil,
          section: section
        )

        if content.nil?
          raise ActiveRecord::RecordNotFound, "Section not found: AFS #{year}:#{number}, § #{section}"
        end

        render json: {
          code: Regulations::Code.from_year_and_number(year, number),
          year: year,
          number: number,
          chapter: nil,
          section: section,
          kind: "section",
          normative_requirement: content[:normative_requirement],
          authoritative_guidance: content[:authoritative_guidance],
          informational_guidance: content[:informational_guidance]
        }
      end

      # GET /api/v1/regulations/:year/:number/chapters/:chapter/sections/:section
      # Get a section with chapter
      def section_with_chapter
        year, number = validate_regulation_params
        chapter = params[:chapter].to_i
        section = params[:section].to_i

        raise ArgumentError, "Invalid chapter parameter" if chapter < 1
        raise ArgumentError, "Invalid section parameter" if section < 1

        content = RegulationContentBuilder.section_content(
          year: year,
          number: number,
          chapter: chapter,
          section: section
        )

        if content.nil?
          raise ActiveRecord::RecordNotFound, "Section not found: AFS #{year}:#{number}, #{chapter} kap., § #{section}"
        end

        render json: {
          code: Regulations::Code.from_year_and_number(year, number),
          year: year,
          number: number,
          chapter: chapter,
          section: section,
          kind: "section",
          normative_requirement: content[:normative_requirement],
          authoritative_guidance: content[:authoritative_guidance],
          informational_guidance: content[:informational_guidance]
        }
      end

      # GET /api/v1/regulations/:year/:number/appendices/:appendix
      # Get an appendix
      def appendix
        year, number = validate_regulation_params
        appendix_id = params[:appendix].to_s.strip

        raise ArgumentError, "Invalid appendix parameter" if appendix_id.blank?

        content_html = RegulationContentBuilder.appendix_html(
          year: year,
          number: number,
          appendix: appendix_id
        )

        if content_html.nil?
          raise ActiveRecord::RecordNotFound, "Appendix not found: AFS #{year}:#{number}, Bilaga #{appendix_id}"
        end

        render json: {
          code: Regulations::Code.from_year_and_number(year, number),
          year: year,
          number: number,
          appendix: appendix_id,
          kind: "appendix",
          content_html: content_html
        }
      end
    end
  end
end
