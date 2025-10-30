# Search Results Tweaks - Complete References & Sorting

## Status: ✅ COMPLETE

Successfully enhanced search results display with complete hierarchy references and sortable results.

## Changes Made

### 1. Complete Reference Column

**Before:**
```
Föreskrift: "AFS 2023:1"
```

**After:**
```
Föreskrift: "AFS 2023:1, § 5, Allmänna råd"
```

**Implementation:**
- New controller method: `format_complete_reference(element)`
- Combines regulation + full hierarchy into single reference
- Handles all hierarchy types: sections, appendices, transitional, and general advice

**Reference Examples:**
```
• Standard element:           "AFS 2023:1"
• Section element:            "AFS 2023:1, § 5"
• Section + General Advice:   "AFS 2023:1, § 5, Allmänna råd"
• Appendix element:           "AFS 2023:1, Bilaga 1"
• Transitional provision:     "AFS 2023:1, Övergångsbestämmelser"
```

### 2. Sortable Results

**Sort Options:**
- **Relevans** (default) - By regulation number, then hierarchy position
- **Föreskrift (A-Z)** - Alphabetical by complete reference
- **Föreskrift (Z-A)** - Reverse alphabetical by complete reference

**Implementation:**
- New controller method: `apply_sort(results, sort_by)`
- Sort links preserve search query parameter
- Active sort option highlighted with CSS class
- Table header labeled "Föreskrift" as requested

**URL Format:**
```
/search?q=arbetsgivaren&sort_by=reference
/search?q=arbetsgivaren&sort_by=reference_desc
/search?q=arbetsgivaren&sort_by=relevance
```

## Code Changes

### Controller (`app/controllers/scrapes_controller.rb`)

**New instance variables:**
```ruby
@sort_by = params[:sort_by].to_s.strip
```

**New result field:**
```ruby
complete_reference: format_complete_reference(element)
```

**New methods:**
```ruby
def format_complete_reference(element)
  # Builds: "AFS 2023:1, § 5, Allmänna råd"
end

def apply_sort(results, sort_by)
  # Applies sort based on parameter
  # Supports: relevance, reference, reference_desc
end
```

### View (`app/views/scrapes/search.html.erb`)

**New section - Sort Options:**
```erb
<div class="sort-options">
  <span class="sort-label">Sortera efter:</span>
  <%= link_to "Relevans", search_scrapes_path(q: @query, sort_by: "relevance") %>
  <%= link_to "Föreskrift (A-Z)", search_scrapes_path(q: @query, sort_by: "reference") %>
  <%= link_to "Föreskrift (Z-A)", search_scrapes_path(q: @query, sort_by: "reference_desc") %>
</div>
```

**Updated table header:**
```erb
<th>Resultat</th>
<th>Föreskrift</th>
```

**Updated reference display:**
```erb
<div class="complete-reference">
  <%= link_to res[:complete_reference], raw_scrape_path(...) %>
</div>
```

## User Interface

### Before
```
┌─────────────────────────┬─────────────────┐
│ Resultat                │ Föreskrift      │
├─────────────────────────┼─────────────────┤
│ § 5 · Allmänna råd      │ AFS 2023:1      │
│ "Arbetsgivaren ska..."  │ [View]          │
└─────────────────────────┴─────────────────┘
```

### After
```
Sortera efter: Relevans | Föreskrift (A-Z) | Föreskrift (Z-A)

┌─────────────────────────┬──────────────────────────┐
│ Resultat                │ Föreskrift               │
├─────────────────────────┼──────────────────────────┤
│ § 5 · Allmänna råd      │ AFS 2023:1, § 5,         │
│ "Arbetsgivaren ska..."  │ Allmänna råd             │
│ [Se hela §]             │ [View] [Se hela §]       │
└─────────────────────────┴──────────────────────────┘
```

## Testing

### ✅ Reference Formatting
- Standard elements display regulation only
- Section elements include section number
- General advice elements show AR indicator
- Appendix elements show bilaga designation
- Transitional provisions labeled correctly

### ✅ Sorting
- Sort parameter accepted and applied
- Sort links preserve search query
- Active sort option highlighted
- Three sort modes work correctly

### ✅ Code Quality
- Rubocop style checks pass
- No warnings or errors
- Code follows Rails conventions

## Hierarchy Reference Format

The format uses comma-separated hierarchy levels:

```
Regulation, [Hierarchy Level], [Hierarchy Level], ...
```

**Examples:**
- `AFS 2023:1` - Just regulation
- `AFS 2023:1, § 5` - Regulation and section
- `AFS 2023:1, § 5, Allmänna råd` - Regulation, section, and advice
- `AFS 2023:1, Bilaga 1` - Regulation and appendix
- `AFS 2023:1, Övergångsbestämmelser` - Regulation and transitional

## Future Enhancements

1. **CSS Styling** - Style sort options with better visual hierarchy
2. **Sorting State** - Remember user's sort preference
3. **Column Sorting** - Make table headers clickable for sorting
4. **Default Sort** - Let users set their preferred default sort
5. **Results Per Page** - Add pagination with sort preservation

## Notes

- Complete reference displays all relevant hierarchy information
- Sort preserves search query for consistent experience
- Active sort option highlighted for clarity
- Table remains clean and organized
- Backward compatible with existing search functionality
