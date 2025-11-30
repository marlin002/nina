# Nina API Documentation

Base URL: `/api/v1`

All endpoints return JSON. The API is read-only and always returns the current version of regulations.

## Endpoints

### List All Regulations

`GET /api/v1/regulations`

Returns a list of all available regulations.

**Response:**
```json
[
  {
    "code": "AFS 2023:1",
    "year": 2023,
    "number": 1,
    "title": "Systematiskt arbetsmiljöarbete – grundläggande skyldigheter för dig med arbetsgivaransvar (AFS 2023:1)"
  },
  ...
]
```

### Get Regulation Structure

`GET /api/v1/regulations/:year/:number/structure`

Returns the structure of a regulation including chapters, sections, and appendices.

**Parameters:**
- `year`: Regulation year (e.g., 2023)
- `number`: Regulation number (e.g., 1, 3, 10)

**Example:** `GET /api/v1/regulations/2023/3/structure`

**Response:**
```json
{
  "code": "AFS 2023:3",
  "year": 2023,
  "number": 3,
  "chapters": [
    {
      "chapter": 1,
      "sections": [1, 2, 3, 4]
    },
    {
      "chapter": 2,
      "sections": [1, 2, 3, ..., 28]
    }
  ],
  "sections_without_chapter": [],
  "appendices": ["1"]
}
```

For regulations without chapters (e.g., AFS 2023:1), the response includes:
```json
{
  "chapters": [],
  "sections_without_chapter": [1, 2, 3, ..., 16],
  "appendices": ["1"]
}
```

### Get Section Content

#### Section with Chapter

`GET /api/v1/regulations/:year/:number/chapters/:chapter/sections/:section`

Returns the full HTML content of a section, including its Allmänna råd (general recommendations) if present.

**Parameters:**
- `year`: Regulation year
- `number`: Regulation number
- `chapter`: Chapter number
- `section`: Section number (paragraf/§)

**Example:** `GET /api/v1/regulations/2023/3/chapters/2/sections/4`

**Response:**
```json
{
  "code": "AFS 2023:3",
  "year": 2023,
  "number": 3,
  "chapter": 2,
  "section": 4,
  "kind": "section",
  "content_html": "<p> Byggherren ska ha rutiner...</p>\n<div class=\"general-recommendation\">...</div>"
}
```

#### Section without Chapter

`GET /api/v1/regulations/:year/:number/sections/:section`

For regulations that don't use chapters (e.g., AFS 2023:1).

**Parameters:**
- `year`: Regulation year
- `number`: Regulation number
- `section`: Section number

**Example:** `GET /api/v1/regulations/2023/1/sections/8`

**Response:**
```json
{
  "code": "AFS 2023:1",
  "year": 2023,
  "number": 1,
  "chapter": null,
  "section": 8,
  "kind": "section",
  "content_html": "<p> Arbetsgivaren ska se till...</p>..."
}
```

### Get Appendix Content

`GET /api/v1/regulations/:year/:number/appendices/:appendix`

Returns the full HTML content of an appendix (Bilaga).

**Parameters:**
- `year`: Regulation year
- `number`: Regulation number
- `appendix`: Appendix identifier (e.g., "1", "2A")

**Example:** `GET /api/v1/regulations/2023/1/appendices/1`

**Response:**
```json
{
  "code": "AFS 2023:1",
  "year": 2023,
  "number": 1,
  "appendix": "1",
  "kind": "appendix",
  "content_html": "<p>Arbetsgivaren ska se till att...</p>..."
}
```

## Error Responses

### 400 Bad Request

Invalid parameters (year out of range, invalid chapter/section number).

```json
{
  "error": "bad_request",
  "message": "Invalid year parameter"
}
```

### 404 Not Found

Regulation, section, or appendix not found.

```json
{
  "error": "not_found",
  "message": "Section not found: AFS 2023:3, 2 kap., § 99"
}
```

## Notes

- All content is returned in Swedish
- HTML content includes semantic structure (paragraphs, lists, etc.)
- Allmänna råd (AR) are included within section content_html when present
- The API always returns the current version of regulations (historical versions not available)
- No authentication required
