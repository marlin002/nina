# Regex Search Feature

## Overview
The regex search feature allows users to search through AFS regulations using regular expressions to find patterns in text. Results show unique matched strings with their frequency counts, sorted alphabetically.

## Usage

### Basic Search (Normal)
Enter a search term without any special delimiters:
```
arbetsmiljö
```
This performs a standard case-insensitive LIKE search.

### Regex Search
Wrap your regex pattern in forward slashes:
```
/arbetsmiljö[a-z]+/
```
This performs a PostgreSQL regex search and shows matched strings with counts.

### Examples

#### Find words starting with "arbets"
```
/arbets\w+/
```

#### Find all AFS references
```
/AFS \d{4}:\d+/
```

#### Find words ending with "het"
```
/\w+het\b/
```

#### Case-insensitive pattern matching
All regex searches are case-insensitive by default (uses PostgreSQL `~*` operator).

## Results Display

### Normal Search Results
- Shows elements with hierarchy (regulation, chapter, section)
- Click through to view full regulation text
- Sortable by reference

### Regex Search Results
- Shows unique matched strings (alphabetically sorted)
- Count of occurrences for each match
- Total unique matches and total occurrences displayed
- No click-through (terminal view)

## Security Features

### 1. Explicit Delimiter Detection
Only queries wrapped in `/pattern/` are treated as regex. This prevents:
- Accidental regex interpretation of special characters
- Users searching for literal strings like `C++` or `(Draft)`

### 2. Syntax Validation
Ruby validates regex syntax before sending to database:
- Invalid patterns show user-friendly error
- Prevents database errors from malformed regex

### 3. ReDoS Protection
PostgreSQL `statement_timeout` set to 2 seconds:
- Prevents catastrophic backtracking patterns like `/(x+x+)+y/`
- Timeout shows helpful error message
- Protects database from CPU exhaustion

### 4. SQL Injection Prevention
All queries use parameterized SQL:
- Pattern values sanitized with `sanitize_sql_array`
- No direct string interpolation in SQL

### 5. Query Length Limit
Same 100-character limit applies to regex searches (including slashes)

## Logging Behavior
- Normal searches: Logged to `search_queries` table
- Regex searches: **NOT logged** (similar to sorted searches)
- Sorted searches: **NOT logged** (already implemented)

## Technical Implementation

### Components
- `RegexSearchService`: Handles regex detection, validation, and execution
- `ScrapesController#search`: Routes to regex or normal search
- `app/views/scrapes/_regex_results.html.erb`: Regex results partial

### PostgreSQL Query
```sql
SELECT matched_string, COUNT(*) as count
FROM (
  SELECT unnest(regexp_matches(text_content, ?, 'gi')) as matched_string
  FROM elements
  WHERE current = true
    AND scrape_id IN (SELECT id FROM scrapes WHERE current = true)
    AND text_content ~* ?
) matches
GROUP BY matched_string
ORDER BY matched_string ASC
LIMIT 500
```

### Key Methods
- `RegexSearchService.regex_search?(query)`: Detects `/pattern/` format
- `RegexSearchService#search(query)`: Executes safe regex search
- Returns: `{ results: [{matched_string: "...", count: n}], total_unique: n, total_occurrences: n, error: nil }`

## Error Handling

### Invalid Regex Syntax
```
/[unclosed/
```
Error: "Ogiltigt regex-mönster. Kontrollera syntaxen."

### Timeout (ReDoS)
```
/(x+x+)+y/
```
Error: "Sökningen tog för lång tid. Prova ett enklare mönster."

### Empty Pattern
```
//
```
Error: "Tomt regex-mönster."

## Limitations
1. No capture groups in results (shows full match only)
2. No click-through from regex results to specific elements
3. 500 result limit for unique matches
4. 2-second query timeout
5. No support for lookahead/lookbehind (depends on PostgreSQL version)

## Testing
Comprehensive test coverage in:
- `test/services/regex_search_service_test.rb` (11 tests)
- `test/controllers/scrapes_controller_test.rb` (5 regex-related tests)

Run tests:
```bash
bin/rails test test/services/regex_search_service_test.rb
bin/rails test test/controllers/scrapes_controller_test.rb
```
