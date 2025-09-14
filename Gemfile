source "https://rubygems.org"

# Rails
gem "rails", "~> 7.2.2", ">= 7.2.2.1"

# Database
gem "pg", ">= 1.4" # Use PostgreSQL for Heroku

# Web Server
gem "puma", ">= 5.0"

# Asset Pipeline
gem "sprockets-rails"
gem "importmap-rails"
gem "dartsass-rails" # For Dart Sass
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

# Background Jobs
gem "sidekiq", ">= 6.0"
gem "redis", ">= 4.0.1" # Required for Sidekiq and caching

# Authentication
gem "devise"
gem "bcrypt", "~> 3.1.7" # Required for Devise

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

# Environment Variables
gem "dotenv-rails", groups: [:development, :test]

# Cron Jobs
gem "whenever", require: false

# Heroku-Specific
gem "rails_12factor", group: :production

group :development, :test do
  gem "sqlite3", ">= 1.4" # Only for development/test
  gem "debug", platforms: %i[mri windows]
  gem "error_highlight", ">= 0.4.0", platforms: [:ruby]
  gem "web-console"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end
