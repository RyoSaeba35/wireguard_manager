source "https://rubygems.org"

# Ruby version lives in .ruby-version (rbenv, CI and Heroku all read it from here)
ruby file: ".ruby-version"

# Rails
gem "rails", "~> 7.2.2", ">= 7.2.2.1"

# Database
gem "pg", ">= 1.4" # Use PostgreSQL for Heroku

# Web Server
gem "puma", "~> 7.0", ">= 7.0.3" # 7.0.3+ recommended by Heroku for Router 2.0

# Asset Pipeline
gem "sprockets-rails"
gem "importmap-rails"
gem "dartsass-rails" # For Dart Sass
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem 'terser'

# Background Jobs
gem "sidekiq", ">= 7.0"
gem 'sidekiq-cron'
gem "redis", ">= 4.0.1" # Required for Sidekiq and caching

# Authentication
gem "devise"
gem "bcrypt", "~> 3.1.7" # Required for Devise
gem "devise-jwt"

# API CORS
gem "rack-cors"

# Rate limiting (login brute-force protection) - see config/initializers/rack_attack.rb
gem "rack-attack", "~> 6.7"

# JSON serialization
gem "active_model_serializers"

# Forms and Styling
gem "simple_form"
gem "bootstrap", "~> 5.3"
# gem "tailwindcss-rails"

# Utilities
gem "bootsnap", require: false
gem "tzinfo-data", platforms: %i[windows jruby]
gem "image_processing", "~> 1.2"
gem "rqrcode"
gem "lockbox"
gem 'sassc', '~> 2.4'
gem 'sassc-rails'


# SSH and File Transfer
gem "net-ssh", ">= 6.0"
gem "net-scp", ">= 3.0"
gem "net-sftp", ">= 3.0"
gem "ed25519", "~> 1.2"
gem "bcrypt_pbkdf", "~> 1.0"

gem 'rbnacl', '~> 7.1'

gem 'aws-sdk-s3', '~> 1.11'

# Environment Variables
gem "dotenv-rails", groups: [:development, :test]


# Heroku-Specific
gem "rails_12factor", group: :production

# Paiment system
gem 'stripe'

gem 'net-http'
gem 'httparty'

gem 'kaminari'

group :development, :test do
  gem "sqlite3", ">= 1.4" # Only for development/test
  gem "debug", platforms: %i[mri windows]
  gem "error_highlight", ">= 0.4.0", platforms: [:ruby]
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

# Debug console on error pages, development only (it refuses to run in test)
group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
