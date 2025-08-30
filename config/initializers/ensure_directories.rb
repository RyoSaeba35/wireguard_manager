# config/initializers/ensure_directories.rb
Rails.application.config.after_initialize do
  config_dir = Rails.root.join('public', 'configs')
  Dir.mkdir(config_dir) unless Dir.exist?(config_dir)

  qr_dir = Rails.root.join('public', 'qr_codes')
  Dir.mkdir(qr_dir) unless Dir.exist?(qr_dir)
end
