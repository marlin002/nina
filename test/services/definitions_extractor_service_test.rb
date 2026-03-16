require "test_helper"

class DefinitionsExtractorServiceTest < ActiveSupport::TestCase
  test "extracts from current scrapes only and removes duplicates reliably" do
    source = sources(:one)
    now = Time.current

    Scrape.unscoped.insert_all!(
      [
        {
          source_id: source.id,
          url: source.url,
          raw_html: <<~HTML,
            <html><body>
              <table>
                <tr><th>Begrepp</th><th>Betydelse</th></tr>
                <tr><td>  Arbetsmiljö </td><td> Miljön på arbetsplatsen </td></tr>
                <tr><td>Skydd</td><td>Åtgärder</td></tr>
                <tr><td>a) Maskin</td><td>Maskiner och teknisk utrustning</td></tr>
                <tr><td>arbetsmiljö</td><td>MILJÖN PÅ ARBETSPLATSEN</td></tr>
              </table>
            </body></html>
          HTML
          title: "Current definitions",
          fetched_at: now,
          current: true,
          superseded_at: nil,
          version: 101,
          created_at: now,
          updated_at: now
        },
        {
          source_id: source.id,
          url: source.url,
          raw_html: <<~HTML,
            <html><body>
              <table>
                <tr><td>Begrepp</td><td>Betydelse</td></tr>
                <tr><td>arbetsmiljö</td><td>Miljön på arbetsplatsen</td></tr>
                <tr><td>Definition</td><td>Beskrivning</td></tr>
              </table>
              <table>
                <tr><th>Namn</th><th>Innehåll</th></tr>
                <tr><td>Ignored</td><td>Ignored</td></tr>
              </table>
            </body></html>
          HTML
          title: "Historical definitions",
          fetched_at: now,
          current: false,
          superseded_at: 1.day.ago,
          version: 102,
          created_at: now,
          updated_at: now
        },
        {
          source_id: source.id,
          url: "#{source.url}?v=2",
          raw_html: <<~HTML,
            <html><body>
              <table>
                <tr><th>Begrepp</th><th>Betydelse</th></tr>
                <tr><td> SKYDD </td><td> åtgärder </td></tr>
                <tr><td>b) maskin</td><td>maskiner och teknisk utrustning</td></tr>
                <tr><td>Risk</td><td>Något som kan orsaka skada</td></tr>
              </table>
            </body></html>
          HTML
          title: "Second current definitions",
          fetched_at: now,
          current: true,
          superseded_at: nil,
          version: 103,
          created_at: now,
          updated_at: now
        }
      ]
    )

    assert_equal(
      [
        { begrepp: "Arbetsmiljö", betydelse: "Miljön på arbetsplatsen" },
        { begrepp: "Maskin", betydelse: "Maskiner och teknisk utrustning" },
        { begrepp: "Risk", betydelse: "Något som kan orsaka skada" },
        { begrepp: "Skydd", betydelse: "Åtgärder" }
      ],
      DefinitionsExtractorService.call
    )
  end
end
