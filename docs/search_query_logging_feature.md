# Search Query Logging and Display Feature

## Overview
Implemented a feature to track and display user search queries with match counts, providing recent and popular search suggestions on the index page. Updated to allow duplicate queries with timestamps and show popularity by usage frequency rather than match count.

## Final Modifications
- **Panel Placement**: Moved search panels below regulation cards (AFS 2023:1, etc.) for better visual hierarchy
- **Numbered Lists**: Changed from tag-style suggestions to numbered ordered lists (1. hjälm, 2. säkerhet, etc.)
- **Time Stamps**: Added "time ago" display for recent searches (e.g., "2 hours ago", "just now")
- **Popularity by Usage**: Popular searches now ranked by frequency of use (number of times searched) rather than result count
- **Duplicate Queries**: Removed uniqueness constraint to allow tracking each search as a separate record with timestamp
- **Time Limit**: Limited all searches to within the last year for relevance

## Changes Made

### 1. Database Migrations
**Initial Migration**: `db/migrate/20251110204156_create_search_queries.rb`

Created `search_queries` table with:
- `query` (string, required): The search query text
- `match_count` (integer, required, default: 0): Number of matching results
- `created_at` (timestamp): When the search was performed
- `updated_at` (timestamp): System timestamp
- Indexes on `query` and `created_at` for efficient lookups

**Updated Migration**: `db/migrate/20251110211248_remove_uniqueness_from_search_queries.rb`
- Removed uniqueness constraint on `query` column
- Allows duplicate queries with different timestamps for frequency tracking

### 2. SearchQuery Model
**File**: `app/models/search_query.rb`

Implemented model with:
- **Validations**:
  - `query`: presence (no uniqueness constraint to allow duplicates)
  - `match_count`: presence and non-negative integer validation
- **Scopes**:
  - `recent_year`: Filters to searches from last year
  - `recent`: Returns up to 10 most recent searches within last year (ordered by created_at DESC)
  - `popular`: Returns up to 10 unique queries grouped by usage frequency, limited to last year (ordered by COUNT DESC)
- **Class method**:
  - `log_search(query, match_count)`: Creates a new record (allows duplicates with timestamps)
- **Instance method**:
  - `time_ago`: Returns human-readable time ago ("just now", "2 min ago", "3 h ago", etc.)

### 3. ScrapesController Updates
**File**: `app/controllers/scrapes_controller.rb`

**Index action**:
- Loads `@recent_searches` and `@popular_searches` for display on index page

**Search action**:
- Calls `SearchQuery.log_search(@query, @results.size)` after performing search
- Logs search with match count to database for tracking and display
- Removed old plain-text logging methods

### 4. Index View Updates
**File**: `app/views/scrapes/index.html.erb`

Added search panels section (positioned after regulation cards):
- **Senaste sökningar** (Recent Searches):
  - Numbered ordered list (1., 2., 3., etc.)
  - Format: "1. query" with "2 hours ago" timestamp below
  - Shows 10 most recent searches from last year
  - Each link reruns that search
- **Populära sökningar** (Popular Searches):
  - Numbered ordered list by usage frequency
  - Format: "1. query (N resultat)" where N is search count
  - Shows unique queries ranked by how many times they were searched
  - Panels styled as cards similar to regulation cards with hover effects

### 5. CSS Styling
**File**: `app/assets/stylesheets/scrapes.css`

Added styling for search panels with:
- `.search-panels`: Grid layout (similar to regulation cards, 350px minmax)
- `.search-panel`: Card-style panels with border, shadow, and hover effects (matches regulation cards)
- `.search-list`: Ordered list (decimal numbering) with proper padding
- `.search-link`: Blue clickable links with underline on hover
- `.search-time`: Gray timestamp text below recent searches
- `.search-meta`: Gray metadata text for result count on popular searches
- Responsive design that stacks to single column on mobile (max-width 768px)

## Technical Details

### Search Query Logging Flow
1. User enters a search query and submits the form
2. `ScrapesController#search` processes the query through `ElementSearchService`
3. After sorting results, `SearchQuery.log_search(@query, @results.size)` is called
4. The model finds or creates the query record and updates match count and timestamp

### Scope Behavior
- **Recent searches**: Updated timestamp on each search, so same query executed later moves to top
- **Popular searches**: Updates match count, so queries with more hits rank higher
- Both scopes return maximum 10 records, perfect for display on index page

### UI Integration
- Search panels automatically hide if no queries have been logged yet
- Each panel conditionally renders only if it has searches to display
- Links use proper Rails path helpers (`search_scrapes_path`) with query parameters
- Recent searches shown as plain text links; popular searches include match counts

## Testing
Successfully tested with:
- Model validations and uniqueness constraints
- Logging behavior: new queries created, existing queries updated
- Scope ordering: recent by creation time, popular by match count
- View rendering with test data
- CSS compilation with no errors
- Form submissions with proper URL generation

## Usage
Once deployed, the feature automatically starts tracking search queries. Each time a user performs a search, the query and result count are saved. The index page displays:
- Up to 10 most recent searches
- Up to 10 most popular searches (by result count)

Clicking any search suggestion reruns that exact query.
