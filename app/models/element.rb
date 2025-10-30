class Element < ApplicationRecord
  belongs_to :scrape

  validates :scrape_id, presence: true
  validates :tag_name, presence: true
  validates :html_snippet, presence: true
  validates :version, presence: true, numericality: { greater_than: 0 }

  # Scopes for versioning
  scope :current, -> { where(current: true) }
  scope :historical, -> { where(current: false) }
  scope :by_scrape, ->(scrape) { where(scrape: scrape) }

  # Scopes for hierarchy
  scope :by_regulation, ->(regulation) { where(regulation: regulation) }
  scope :by_chapter, ->(chapter) { where(chapter: chapter) }
  scope :by_section, ->(section) { where(section: section) }
  scope :by_appendix, ->(appendix) { where(appendix: appendix) }
  scope :in_transitional, -> { where(is_transitional: true) }
  scope :in_general_recommendation, -> { where(is_general_recommendation: true) }

  # Default scope: only show current elements
  default_scope { current }

  # Versioning methods
  def supersede!
    update!(current: false, superseded_at: Time.current)
  end

  def next_version_number
    Element.unscoped.where(scrape: scrape).maximum(:version) || 0 + 1
  end

  # Reconstruct a paragraph/section from its constituent elements
  def self.reconstruct_section(scrape, section_number)
    elements = unscoped.where(scrape: scrape, section: section_number, current: true, is_general_recommendation: false)
    html_parts = elements.order(:position_in_parent, :id).pluck(:html_snippet)
    html_parts.join("\n")
  end

  # Reconstruct a section with its general advice (Allmänna råd)
  # Returns a hash with :section_html and :advice_html (if any)
  def self.reconstruct_section_with_advice(scrape, section_number)
    # Get the main section content (excluding general recommendations)
    section_elements = unscoped.where(
      scrape: scrape,
      section: section_number,
      current: true,
      is_general_recommendation: false
    )
    section_html = section_elements.order(:position_in_parent, :id).pluck(:html_snippet).join("\n")

    # Get the general advice for this section
    advice_elements = unscoped.where(
      scrape: scrape,
      section: section_number,
      current: true,
      is_general_recommendation: true
    )
    advice_html = advice_elements.order(:position_in_parent, :id).pluck(:html_snippet).join("\n")

    {
      section: section_number,
      section_html: section_html,
      advice_html: advice_html.present? ? advice_html : nil,
      has_advice: advice_html.present?
    }
  end

  # Reconstruct an appendix from its constituent elements
  def self.reconstruct_appendix(scrape, appendix_identifier)
    elements = unscoped.where(scrape: scrape, appendix: appendix_identifier, current: true)
    html_parts = elements.order(:position_in_parent, :id).pluck(:html_snippet)
    html_parts.join("\n")
  end

  # Reconstruct the appropriate construct for an element based on its hierarchy
  # For an element, determine what it belongs to (paragraph, transitional rules, or appendix)
  # and reconstruct that entire construct
  def self.reconstruct_from_element(element)
    return nil unless element

    if element.is_transitional?
      reconstruct_transitional_rules(element.scrape)
    elsif element.appendix.present?
      reconstruct_appendix(element.scrape, element.appendix)
    elsif element.section.present?
      reconstruct_section_with_advice(element.scrape, element.section)
    end
  end

  # Reconstruct all transitional rules (Övergångsbestämmelser)
  # Returns combined HTML of all transitional elements
  def self.reconstruct_transitional_rules(scrape)
    elements = unscoped.where(scrape: scrape, current: true, is_transitional: true)
    html_parts = elements.order(:position_in_parent, :id).pluck(:html_snippet)
    html_parts.join("\n")
  end

  # Get all elements for a given hierarchy level
  def self.for_hierarchy(scrape, hierarchy_params)
    elements = unscoped.where(scrape: scrape, current: true)

    elements = elements.where(regulation: hierarchy_params[:regulation]) if hierarchy_params[:regulation]
    elements = elements.where(chapter: hierarchy_params[:chapter]) if hierarchy_params[:chapter]
    elements = elements.where(section: hierarchy_params[:section]) if hierarchy_params[:section]
    elements = elements.where(appendix: hierarchy_params[:appendix]) if hierarchy_params[:appendix]
    elements = elements.where(is_transitional: true) if hierarchy_params[:is_transitional]
    elements = elements.where(is_general_recommendation: true) if hierarchy_params[:is_general_recommendation]

    elements.order(:position_in_parent, :id)
  end
end
