# Set default locale to Swedish and enable fallbacks
I18n.available_locales = [ :sv, :en ]
I18n.default_locale = :sv
I18n.enforce_available_locales = true

# Ensure application loads all locale files, including nested ones
I18n.load_path += Dir[Rails.root.join("config", "locales", "**", "*.{rb,yml}")]
