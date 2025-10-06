module ApplicationHelper
  # Extract and format regulation number from source URL
  # e.g. "https://...afs-20231/" -> "1", "...afs-202310/" -> "10"
  def regulation_number(url)
    match = url.match(/afs-2023(\d+)/)
    match ? match[1] : "?"
  end
  
  # Format full regulation name
  # e.g. "https://...afs-20231/" -> "AFS 2023:1"
  def regulation_name(url)
    "AFS 2023:#{regulation_number(url)}"
  end
  
  # Extract article preview from HTML content
  # Finds the first .section-sign element (e.g., "1 §") and the following paragraph
  def section_preview(raw_html, length_limit = 200)
    return "No content available" if raw_html.blank?
    
    begin
      doc = Nokogiri::HTML(raw_html)
      first_section = doc.css('.section-sign').first
      
      if first_section
        section_text = first_section.text.strip
        
        # Find the next element that contains content
        next_element = first_section.next_element
        while next_element && next_element.text.strip.blank?
          next_element = next_element.next_element
        end
        
        if next_element
          paragraph_text = next_element.text.strip
          combined_text = "#{section_text} #{paragraph_text}"
          # Manual truncation with ellipsis
          return combined_text.length > length_limit ? 
                 "#{combined_text[0, length_limit-3]}..." : 
                 combined_text
        else
          return section_text
        end
      else
        # Fallback: use first paragraph or plain text extraction
        first_paragraph = doc.css('p').first
        if first_paragraph
          text = first_paragraph.text.strip
          return text.length > length_limit ? 
                 "#{text[0, length_limit-3]}..." : 
                 text
        else
          # Final fallback: use existing plain_text logic
          plain_text = doc.text.gsub(/\s+/, ' ').strip
          return plain_text.length > length_limit ? 
                 "#{plain_text[0, length_limit-3]}..." : 
                 plain_text
        end
      end
    rescue => e
      Rails.logger.warn "Error extracting section preview: #{e.message}"
      return "Preview not available"
    end
  end
  
  # Count the number of articles in HTML content
  # Counts .section-sign elements (e.g., "1 §", "2 §", etc.)
  def article_count(raw_html)
    return 0 if raw_html.blank?
    
    begin
      doc = Nokogiri::HTML(raw_html)
      doc.css('.section-sign').length
    rescue => e
      Rails.logger.warn "Error counting articles: #{e.message}"
      0
    end
  end
  
  # Extract regulation subject/topic from HTML content
  # Looks for meaningful headings or contextual clues about the regulation's purpose
  def regulation_subject(raw_html)
    return "Work Environment Regulation" if raw_html.blank?
    
    begin
      doc = Nokogiri::HTML(raw_html)
      
      # Strategy 1: Look for meaningful h2 headings that indicate subject matter
      headings = doc.css('h2')
      
      # Look for headings that contain key subject indicators
      subject_headings = headings.select do |h|
        text = h.text.strip.downcase
        # Look for headings that seem to describe the regulation's scope or topic
        text.match?(/(organisatorisk|social|arbetsmiljö|byggnads|konstruktion|maskin|kemisk|tryck|explosiv|personlig|skydd)/)
      end
      
      if subject_headings.any?
        subject = subject_headings.first.text.strip
        # Clean up the subject text
        subject = subject.gsub(/^\d+\s+kap\.\s*/i, '') # Remove "2 kap. "
        subject = subject.gsub(/^avdelning\s+[IVX]+:\s*/i, '') # Remove "Avdelning II: "
        return subject if subject.length > 10
      end
      
      # Strategy 2: Look for keywords in the purpose section (after "Syftet")
      first_section = doc.css('.section-sign').first
      if first_section
        next_element = first_section.next_element
        while next_element && next_element.text.strip.blank?
          next_element = next_element.next_element
        end
        
        if next_element
          purpose_text = next_element.text.strip
          # Extract key topic from purpose statement
          if purpose_text.match?(/(byggnads|byggarbete|konstruktion)/i)
            return "Construction and Building Work"
          elsif purpose_text.match?(/(maskin|utrustning|verktyg)/i)
            return "Machinery and Equipment"
          elsif purpose_text.match?(/(kemisk|ämne|exponering)/i)
            return "Chemical Substances and Exposure"
          elsif purpose_text.match?(/(systematisk.*arbetsmiljö)/i)
            return "Systematic Work Environment Management"
          elsif purpose_text.match?(/(arbetsplats|lokalutformning)/i)
            return "Workplace Design"
          elsif purpose_text.match?(/(arbetstid|vila)/i)
            return "Working Time and Rest"
          end
        end
      end
      
      # Strategy 3: Generic fallback
      return "Work Environment Regulation"
      
    rescue => e
      Rails.logger.warn "Error extracting regulation subject: #{e.message}"
      return "Work Environment Regulation"
    end
  end
  
  # Extract the subject part from the stored regulation title
  # e.g. "Systematiskt arbetsmiljöarbete – grundläggande skyldigheter för dig med arbetsgivaransvar (AFS 2023:1)" 
  #   -> "Systematiskt arbetsmiljöarbete – grundläggande skyldigheter för dig med arbetsgivaransvar"
  def regulation_title_subject(title)
    return "Work Environment Regulation" if title.blank?
    
    # Remove the (AFS 2023:X) part from the end
    title.gsub(/\s*\(AFS\s+\d{4}:\d+\)\s*$/, '').strip
  end
end
