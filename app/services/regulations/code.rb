module Regulations
  # Helper module for working with regulation codes like "AFS 2023:3"
  module Code
    # Convert year and number to regulation code
    # @param year [Integer] Year (e.g. 2023)
    # @param number [Integer] Number (e.g. 3)
    # @return [String] Code like "AFS 2023:3"
    def self.from_year_and_number(year, number)
      "AFS #{year}:#{number}"
    end

    # Parse regulation code into year and number
    # @param code [String] Code like "AFS 2023:3"
    # @return [Hash, nil] Hash with :year and :number keys, or nil if invalid
    def self.parse(code)
      return nil if code.blank?

      match = code.match(/AFS\s*(\d{4}):(\d+)/i)
      return nil unless match

      {
        year: match[1].to_i,
        number: match[2].to_i
      }
    end

    # Extract regulation code from a URL
    # @param url [String] URL like "https://...afs-20233/..."
    # @return [String, nil] Code like "AFS 2023:3" or nil
    def self.from_url(url)
      match = url.match(/afs-(\d{4})(\d+)/)
      return nil unless match

      from_year_and_number(match[1].to_i, match[2].to_i)
    end

    # Check if a string is a valid regulation code
    # @param code [String] Potential regulation code
    # @return [Boolean]
    def self.valid?(code)
      !parse(code).nil?
    end
  end
end
