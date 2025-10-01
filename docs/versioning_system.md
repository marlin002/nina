# Data Versioning System

This document describes the versioning system implemented for historical data tracking in the Nina application.

## 🎯 **Purpose**

The versioning system ensures that:
- **Current data only**: Default queries return only the latest version of data
- **History preserved**: All previous versions are maintained in the database
- **Change tracking**: When content changes, new versions are created instead of updates
- **Audit trail**: Complete history with timestamps of when versions were superseded

## 🏗️ **Architecture**

### **Single Table with Version Fields** (Recommended Approach)

Both `sources` and `articles` tables include versioning fields:

```ruby
# Versioning fields added to both tables:
- current: boolean (default: true, indexed)
- version: integer (default: 1, auto-increment per URL)
- superseded_at: timestamp (when record became historical)
```

### **Database Indexes**

Optimized for fast queries:
```ruby
# Articles
add_index :articles, :current
add_index :articles, [:url, :source_id, :version]
add_index :articles, [:url, :source_id, :current]

# Sources  
add_index :sources, :current
add_index :sources, [:url, :version]
add_index :sources, [:url, :current], unique: true, where: "current = true"
```

## 🔍 **Query Patterns**

### **Default Behavior (Current Data Only)**

```ruby
# These return only current versions:
Article.all                    # Only current articles
Source.all                     # Only current sources
Article.count                  # Count of current articles
source.articles                # Current articles for source
```

### **Historical Data Access**

```ruby
# Access all versions:
Article.unscoped.all           # All versions of all articles
Article.unscoped.historical    # Only historical (superseded) versions

# Specific article history:
article.all_versions           # All versions of this article
article.previous_version       # Previous version
article.next_version          # Next version (if exists)

# Version navigation:
Article.unscoped.where(url: url).versions  # All versions by version number
```

### **Mixed Queries**

```ruby
# Current articles with historical context:
current_article = Article.find_by(url: url)
all_versions = current_article.all_versions.count

# Historical analysis:
Article.unscoped.historical.where(created_at: 1.month.ago..)
```

## 🔄 **Versioning Workflow**

### **Content Scraping Process**

1. **Check existing**: Find current version for URL + source
2. **Content comparison**: Compare new content with existing
3. **Version creation**: If content changed:
   - Mark current version as historical (`current: false`, set `superseded_at`)
   - Create new version (`version: previous_version + 1`, `current: true`)
4. **No change**: Skip creation, log "unchanged"

### **Example Flow**

```ruby
# First scrape - creates version 1
article_v1 = Article.create!(
  title: "Original Title",
  url: "https://example.com/article",
  content: "Original content",
  version: 1,
  current: true
)

# Content changes - creates version 2
existing = Article.find_by(url: url, current: true)
existing.supersede!  # Sets current: false, superseded_at: Time.current

article_v2 = Article.create!(
  title: "Updated Title", 
  url: "https://example.com/article",
  content: "Updated content",
  version: 2,          # Auto-incremented
  current: true        # New current version
)
```

## 📊 **Model Methods**

### **Article & Source Models**

```ruby
# Scopes
.current                       # Current versions only
.historical                    # Historical versions only  
.versions                      # Order by version number
.for_url(url)                 # All versions for specific URL

# Instance Methods
article.supersede!             # Mark as historical
article.next_version_number    # Calculate next version
article.all_versions          # All versions of this URL
article.previous_version      # Previous version
article.next_version          # Next version
article.current_version?      # Is this the current version?
```

## 🛠️ **Usage Examples**

### **Querying Current Data**

```ruby
# Normal usage - only current data
recent_articles = Article.recent.limit(10)
source_articles = Article.by_source(source)
total_current = Article.count

# All work with current data only due to default scope
```

### **Accessing History**

```ruby
# View all versions of an article
article = Article.find_by(url: "https://example.com/article")
versions = article.all_versions
puts "#{versions.count} versions found"

# Compare current vs previous
current = article
previous = article.previous_version
if previous
  puts "Title changed from '#{previous.title}' to '#{current.title}'"
  puts "Previous version superseded at: #{previous.superseded_at}"
end

# Historical analysis
superseded_today = Article.unscoped.historical
                          .where(superseded_at: Date.current.all_day)
puts "#{superseded_today.count} articles updated today"
```

### **Version Navigation**

```ruby
# Get specific version
article_v1 = Article.unscoped.find_by(url: url, version: 1)
article_v2 = Article.unscoped.find_by(url: url, version: 2)

# Navigate versions
current = Article.find_by(url: url)  # Always gets current version
first_version = current.all_versions.first
latest_version = current.all_versions.last  # Same as current
```

## ⚡ **Performance Considerations**

### **Optimizations**

- **Default scope**: `Article.all` uses `WHERE current = true` index
- **Composite indexes**: Fast lookups by URL + source + version
- **Partial unique constraint**: Only one current version per URL
- **Historical queries**: Use `unscoped` to bypass default scope

### **Query Performance**

```ruby
# FAST - uses current index
Article.where(source: source).count

# FAST - composite index  
Article.find_by(url: url, source: source, current: true)

# SLOW - full table scan (use sparingly)
Article.unscoped.where("created_at > ?", 1.year.ago)
```

## 🔧 **Management Tasks**

### **Rake Tasks Updated**

All existing rake tasks work with current data only:

```bash
rails scrape:status    # Shows current articles only
rails scrape:all       # Scrapes current sources only
```

### **Seeding with Versioning**

Seeds create version 1 of each source:

```ruby
# db/seeds.rb creates initial versions
Source.create!(url: url, version: 1, current: true)
```

## 🚨 **Important Notes**

### **Breaking Changes**

- **Default scope**: `Article.all` and `Source.all` now default to current only
- **Explicit unscoped**: Use `Article.unscoped` to access all versions
- **Count changes**: `Article.count` returns current count, not total

### **Migration Safety**

- ✅ **Backward compatible**: Existing data gets `current: true, version: 1`
- ✅ **Index optimized**: New indexes support fast current-only queries  
- ✅ **Constraint updated**: Sources can have multiple versions, but only one current per URL

### **Memory Considerations**

- Historical data accumulates over time
- Consider archiving very old versions if needed
- Monitor database size growth
- Indexes maintain query performance

## ✨ **Benefits**

- 🔍 **Current data fast**: Default queries are optimized for current data
- 📚 **Complete history**: No data loss, full audit trail
- 🔄 **Change tracking**: Know exactly when and what changed
- 🚀 **Performance**: Indexed queries remain fast
- 🛡️ **Data integrity**: Referential integrity maintained across versions