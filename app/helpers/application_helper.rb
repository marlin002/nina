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

  # Count the number of general recommendations in HTML content
  # Counts div.general-recommendation elements
  def general_recommendation_count(raw_html)
    return 0 if raw_html.blank?

    begin
      doc = Nokogiri::HTML(raw_html)
      doc.css('div.general-recommendation').length
    rescue => e
      Rails.logger.warn "Error counting general recommendations: #{e.message}"
      0
    end
  end

  # Count the number of appendices in HTML content
  # Looks for h2 elements with an id that starts with "bilaga" (case-insensitive)
  def appendix_count(raw_html)
    return 0 if raw_html.blank?

    begin
      doc = Nokogiri::HTML(raw_html)
      doc.css('h2[id]').count { |h| h['id'].to_s.downcase.start_with?('bilaga') }
    rescue => e
      Rails.logger.warn "Error counting appendices: #{e.message}"
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

  # Normalize NBSP to regular spaces
  def normalize_nbsp_spaces(str)
    str.to_s.tr("\u00A0", ' ')
  end

  # Collapse runs of whitespace (including NBSP) to single spaces and strip ends
  def collapse_whitespace(str)
    normalize_nbsp_spaces(str).gsub(/[\s\u00A0]+/, ' ').strip
  end

  # Highlight occurrences of query in text, returning safe HTML with <mark> tags.
  # Treat spaces in the query as matching both regular spaces and NBSP in the text.
  def highlight_matches(text, query)
    return h(text.to_s) if text.blank? || query.blank?

    # Build a flexible regex: spaces in query become [\s\u00A0]+ to match NBSP and spaces in content
    q = normalize_nbsp_spaces(query.to_s).strip
    escaped = Regexp.escape(q)
    flex = escaped.gsub(/\s+/, '[\s\u00A0]+')
    pattern = Regexp.new(flex, Regexp::IGNORECASE)

    str = text.to_s
    result = +''
    last_idx = 0

    str.to_enum(:scan, pattern).each do
      m = Regexp.last_match
      result << ERB::Util.html_escape(str[last_idx...m.begin(0)])
      # Avoid content_tag here so this helper works from controller context too
      result << "<mark>#{ERB::Util.html_escape(m[0])}</mark>"
      last_idx = m.end(0)
    end
    result << ERB::Util.html_escape(str[last_idx..-1])

    result.html_safe
  end

  # Assign synthetic ids to all elements with inner text that lack an id, in document order.
  # Returns the same fragment/doc after mutation. IDs are in the form "benina-n-<sequence>".
  def assign_synthetic_ids!(fragment)
    seq = 0
    fragment.css('*').each do |node|
      # Faster check for presence of any non-whitespace text in subtree
      has_text = node.xpath('.//text()[normalize-space()]').any?
      next unless has_text
      if node['id'].to_s.strip.empty?
        node['id'] = "benina-n-#{seq}"
        seq += 1
      end
    end
    fragment
  end

  # Highlight all matches for the query across the entire fragment by wrapping in <mark>.
  # Skips script and style tags.
  def highlight_all_matches_in_fragment!(fragment, query)
    return fragment if query.blank?
    pattern = Regexp.new(Regexp.escape(query.to_s), Regexp::IGNORECASE)

    fragment.traverse do |node|
      next unless node.text?
      parent = node.parent
      next if parent.nil?
      tag = parent.name&.downcase
      next if tag == 'script' || tag == 'style'

      original = node.text
      next unless original.match?(pattern)

      highlighted_html = highlight_matches(original, query)
      replacement = Nokogiri::HTML::DocumentFragment.parse(highlighted_html)
      node.replace(replacement)
    end

    fragment
  end

  # Produce enriched HTML for the raw view: ensure synthetic IDs exist and optionally highlight matches
  # in the entire fragment.
  def enrich_html_with_ids_and_highlights(raw_html, query = nil)
    return raw_html.to_s if raw_html.blank?
    fragment = Nokogiri::HTML::DocumentFragment.parse(raw_html.to_s)
    assign_synthetic_ids!(fragment)
    highlight_all_matches_in_fragment!(fragment, query)
    fragment.to_html
  end

  # Build a context index for a fragment mapping element id => { kap:, paragraf:, bilaga: }
  # Uses the following heuristics (NBSP-aware):
  # - "X kap." from h3 text beginning with "X kap." or "X kapitel"
  # - "X §" from span.section-sign text (e.g., "1 §")
  # - "Bilaga X" from h2 id starting with "bilagaX..." or h2 text beginning with "Bilaga X"
  def extract_context_index(fragment)
    index = {}
    current_kap = nil
    current_par = nil
    current_bilaga = nil

    fragment.traverse do |node|
      next unless node.element?
      tag = node.name.to_s.downcase

      if tag == 'h3'
        txt = collapse_whitespace(node.text)
        if (m = txt.match(/\A(\d+)\s*(?:kap\.|kapitel)/i))
          current_kap = m[1].to_i
        end
      elsif tag == 'span' && node['class'].to_s.split(' ').include?('section-sign')
        txt = normalize_nbsp_spaces(node.text)
        if (m = txt.match(/\A\s*(\d+)\s*§\b/))
          current_par = m[1].to_i
        end
      elsif tag == 'h2'
        id = node['id'].to_s
        # Capture only the leading digits after 'bilaga', ignore any trailing slug text
        if (m = id.downcase.match(/\Abilaga(\d+)/))
          current_bilaga = m[1].to_i
        else
          # NBSP-aware: allow Bilaga&nbsp;X
          txt_raw = node.text.to_s
          txt = normalize_nbsp_spaces(txt_raw)
          if (m2 = txt.match(/\ABilaga[\s\u00A0]*(\d+)/i))
            current_bilaga = m2[1].to_i
          end
        end
      end

      eid = node['id'].to_s
      next if eid.strip.empty?
      # Only record for elements that actually contain some text in subtree
      has_text = node.xpath('.//text()[normalize-space()]').any?
      next unless has_text

      index[eid] = { kap: current_kap, paragraf: current_par, bilaga: current_bilaga }
    end

    index
  end

  # Format the context label in order: "# kap.; # §; Bilaga #"
  def format_context_label(ctx)
    return '' if ctx.nil?
    parts = []
    if ctx[:kap]
      parts << "#{ctx[:kap]} kap."
    end
    if ctx[:paragraf]
      parts << "#{ctx[:paragraf]} §"
    end
    if ctx[:bilaga]
      parts << "Bilaga #{ctx[:bilaga]}"
    end
    parts.join('; ')
  end

  # Find the nearest paragraph number ("X §") relative to a node by inspecting
  # the node itself, its previous siblings (and their descendants), and then
  # walking up ancestors with a bounded search. NBSP-aware.
  def find_nearest_paragraph_number(node, max_ancestor_hops = 12)
    return nil if node.nil?

    # Helper to parse number from a section-sign element or text
    parse_from_sign = lambda do |sign_node|
      return nil unless sign_node
      txt = normalize_nbsp_spaces(sign_node.text)
      if (m = txt.match(/\b(\d+)\s*§\b/))
        return m[1].to_i
      end
      sid = sign_node['id'].to_s
      if (m = sid.match(/(\d+)\s*§?/))
        return m[1].to_i
      end
      nil
    end

    # Walk up ancestors; at each level, check within current, then previous siblings deeply
    current = node
    hops = 0
    while current && hops <= max_ancestor_hops
      # 1) Inside current node
      sign = current.at_css('span.section-sign')
      num = parse_from_sign.call(sign)
      return num if num

      # 2) Previous siblings at this level (search their subtree)
      sib = current.previous_element
      while sib
        sign = sib.at_css('span.section-sign')
        num = parse_from_sign.call(sign)
        return num if num
        # Generic fallback: sibling text contains a section-sign
        t = normalize_nbsp_spaces(sib.text.to_s)
        if (m = t.match(/\b(\d+)\s*§\b/))
          return m[1].to_i
        end
        sib = sib.previous_element
      end

      current = current.parent
      hops += 1
    end

    nil
  end

  # Compose the clickable regulation label according to rules:
  # - Always start with regulation (e.g., "AFS 2023:11").
  # - If bilaga is present, append "Bilaga X" and do not include kap/§.
  # - Else, optionally append "X kap." and/or "Y §" in that order if present.
  def compose_regulation_context(regulation, ctx)
    return regulation.to_s if ctx.nil?

    if ctx[:bilaga].present?
      return "#{regulation} Bilaga #{ctx[:bilaga]}"
    end

    parts = []
    parts << "#{ctx[:kap]} kap." if ctx[:kap]
    parts << "#{ctx[:paragraf]} §" if ctx[:paragraf]
    suffix = parts.join(' ')

    suffix.blank? ? regulation.to_s : "#{regulation} #{suffix}"
  end
end
