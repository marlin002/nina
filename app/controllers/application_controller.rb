class ApplicationController < ActionController::Base
  # Allow browsers from the last few years
  # This supports a wider range of browsers while excluding very old versions
  # See: https://github.com/basecamp/browsers for version options
  # allow_browser versions: :modern  # Too restrictive - only latest browsers
  # Comment out to allow all browsers:
  # allow_browser versions: :modern
end
