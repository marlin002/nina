require "test_helper"

class DefinitionsControllerTest < ActionDispatch::IntegrationTest
  test "index renders consolidated definitions table" do
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
                <tr><td>Risk</td><td>Något som kan orsaka skada</td></tr>
              </table>
            </body></html>
          HTML
          title: "Definitions page content",
          fetched_at: now,
          current: true,
          version: 201,
          created_at: now,
          updated_at: now
        }
      ]
    )

    get definitions_path

    assert_response :success
    assert_select "h1", text: "Alla definitioner"
    assert_select "th", text: "Begrepp"
    assert_select "th", text: "Betydelse"
    assert_select "td", text: "Risk"
    assert_select "td", text: "Något som kan orsaka skada"
  end
end
