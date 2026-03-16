require "redis"
# Detta tvingar Rails att använda miljövariabeln om den finns, annars localhost
redis_url = ENV.fetch("REDIS_URL", "redis://192.168.2.15:6379/0")
REDIS = Redis.new(url: redis_url)
