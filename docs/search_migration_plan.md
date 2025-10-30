# Search Migration Plan: Plain Text → Element-Based

## Current State

**Current Search Implementation** (in `ScrapesController#search`):
1. Searches `Scrape.plain_text` using ILIKE query
2. Returns text snippets with leading/trailing context (60 chars)
3. Results include:
   - `snippet_text`: matched text with context
   - `leading`, `match`, `trailing`: separate components
   - `regulation`: regulation name (e.g., "AFS 2023:1")
   - `subject`: regulation subject/title
   - `scrape`: the parent Scrape object
   - `reg_num`: for sorting
   - `position`: byte position in plain_text

## Proposed Element-Based Search

### Advantages
- **Hierarchical context**: Each result knows its section (§), appendix, general advice status
- **Targeted reconstruction**: Can reconstruct the complete paragraph/section/appendix
- **Better organization**: Results naturally grouped by hierarchy
- **Richer metadata**: Know whether result is in main text or Allmänna råd

### Database Strategy

**No additional indexing needed** - leverage existing:
- `Element.text_content` - already stores extracted text per element
- `Element.section`, `Element.appendix`, `Element.is_general_recommendation` - hierarchy fields
- `Element.html_snippet` - for reconstruction

### Implementation Steps

#### Phase 1: Core Search Method
Create `Element.search(query, limit = 500)` class method:
- Search `Element.text_content` using ILIKE
- Return array of Elements matching the query
- Maintain performance with limit

**SQL Pattern**:
```ruby
Element.unscoped
  .where(current: true)
  .where("text_content ILIKE ?", "%#{escaped_query}%")
  .limit(limit)
```

#### Phase 2: Update Controller
Modify `ScrapesController#search`:
- Replace scrape plain_text search with element search
- Map Element results to a search result hash with hierarchy info
- Format for view presentation

**Result Hash Structure**:
```ruby
{
  element_id: element.id,
  element_text: element.text_content,
  snippet_text: element.text_content,  # full element text (may be short)
  regulation: element.regulation,      # "AFS 2023:1"
  section: element.section,            # 5 (or nil)
  appendix: element.appendix,          # "1" (or nil)
  is_general_recommendation: element.is_general_recommendation,
  is_transitional: element.is_transitional,
  construct_type: determine_construct_type(element),  # :section, :appendix, :transitional
  scrape: element.scrape,
  subject: regulation_title_subject(element.scrape.title),
  position: sort_position  # for ordering within section
}
```

#### Phase 3: Update View
Modify `scrapes/search.html.erb`:
- Display hierarchy in results (§ 5, Bilaga 1, Övergångsbestämmelser)
- Link to full scrape or reconstructed construct
- Show AR indicator if applicable

**Example Display**:
```
§ 5 · Allmänna råd
"Arbetsgivaren har alltid kvar ansvaret för arbetsmiljön..."

AFS 2023:1 →
```

### Migration Details

#### 1. Create Element Search Service (Optional)
```ruby
# app/services/element_search_service.rb
class ElementSearchService
  def search(query, limit: 500)
    return [] if query.blank?
    
    escaped = query.gsub("%", '\\%').gsub("_", '\\_')
    
    Element.unscoped
      .where(current: true)
      .where("text_content ILIKE ?", "%#{escaped}%")
      .includes(:scrape)
      .limit(limit)
  end
end
```

#### 2. Modify Controller
```ruby
def search
  @query = params[:q].to_s.strip
  @results = []
  
  if @query.present?
    elements = ElementSearchService.new.search(@query, limit: 500)
    
    @results = elements.map do |element|
      {
        element: element,
        element_text: element.text_content,
        regulation: element.regulation,
        hierarchy: format_hierarchy(element),  # "§ 5, Allmänna råd"
        construct_type: determine_construct_type(element),
        scrape: element.scrape,
        subject: regulation_title_subject(element.scrape.title)
      }
    end
    
    # Sort by regulation, then by hierarchy position
    @results.sort_by! { |r| [r[:regulation], sort_key(r)] }
  end
end
```

#### 3. Update Routes (if needed)
- May add dedicated element search route
- Keep existing search route for compatibility

### Backward Compatibility

**Option A: Gradual Migration**
- Keep both search methods temporarily
- Add feature flag to switch between them
- Validate results match expected behavior

**Option B: Direct Replacement**
- Replace search completely
- Test thoroughly before deployment
- Include fallback if issues arise

### Benefits Over Current Implementation

| Aspect | Current | Element-Based |
|--------|---------|---------------|
| Search unit | Entire scrape text | Individual elements |
| Hierarchy context | None | Full (§, Bilaga, AR) |
| Result granularity | Byte position in text | Element ID + hierarchy |
| Reconstruction | N/A | Call `reconstruct_from_element` |
| Performance | Full table scan | Index on text_content + limit |
| Memory | Store all plain_text | Store individual text snippets |

### Potential Challenges

1. **Search Performance**: Text search on 323 elements per scrape (vs. 1 plain_text field)
   - Solution: Add index on `elements.text_content`
   - Solution: Limit to 500 results

2. **Element Text vs. Snippet**: Elements may contain less context than original search
   - Solution: Include parent element text in context
   - Solution: Reconstruct full construct for display

3. **Multiple Elements Per Match**: Large sections may have multiple matching elements
   - Solution: Group by construct (section/appendix)
   - Solution: Display construct, not individual elements

### Post-Migration

- **Full-text search**: Consider PostgreSQL full-text search on element text
- **Analytics**: Track which hierarchy levels are searched most
- **UI Enhancement**: Show hierarchy breadcrumb in results
- **Reconstruction API**: Expose reconstruct_from_element as API endpoint

### Testing Strategy

1. Test same queries with both methods
2. Verify result order and count match
3. Check performance with large datasets
4. Validate hierarchy extraction
5. Test edge cases (transitional, appendices, AR)

### Rollout Plan

1. Implement Element.search_service
2. Add controller method alongside current search
3. Test with sample queries
4. Switch views to new results
5. Monitor for issues
6. Remove old plain_text search code
