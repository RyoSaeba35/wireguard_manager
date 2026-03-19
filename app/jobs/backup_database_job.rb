# app/jobs/backup_database_job.rb
class BackupDatabaseJob < ApplicationJob
  queue_as :default

  def perform
    db_config = parse_database_config
    backup_file = "railway_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"
    local_path = "/tmp/#{backup_file}"

    dump_database(db_config, local_path)
    upload_to_wasabi(local_path, backup_file)

    Rails.logger.info "Database backup completed: #{backup_file}"
  rescue => e
    Rails.logger.error "Database backup failed: #{e.message}"
    raise
  ensure
    File.delete(local_path) if local_path && File.exist?(local_path)
  end

  private

  def parse_database_config
    db_url = URI.parse(ENV['DATABASE_URL'])
    {
      host: db_url.host,
      port: db_url.port,
      user: db_url.user,
      password: db_url.password,
      name: db_url.path.delete_prefix('/')
    }
  end

  def dump_database(config, local_path)
    # Use system() with env hash instead of string interpolation
    # to avoid shell injection with credentials
    env = { "PGPASSWORD" => config[:password] }

    success = system(
      env,
      "pg_dump",
      "-F", "p",
      "-h", config[:host],
      "-p", config[:port].to_s,
      "-U", config[:user],
      "-d", config[:name],
      "-f", local_path
    )

    unless success && File.exist?(local_path) && File.size(local_path) > 0
      raise "pg_dump failed or produced an empty file at #{local_path}"
    end

    Rails.logger.info "Database dumped successfully to #{local_path}"
  end

  def upload_to_wasabi(local_path, backup_file)
    s3_client = Aws::S3::Client.new(
      region: ENV['AWS_REGION'],
      endpoint: ENV['AWS_ENDPOINT'],
      access_key_id: ENV['AWS_ACCESS_KEY_ID'],
      secret_access_key: ENV['AWS_SECRET_ACCESS_KEY'],
      force_path_style: true
    )

    File.open(local_path, 'rb') do |file|
      s3_client.put_object(
        bucket: ENV['AWS_BUCKET'],
        key: backup_file,
        body: file
      )
    end

    Rails.logger.info "Backup uploaded to Wasabi: #{backup_file}"
  rescue Aws::S3::Errors::ServiceError => e
    Rails.logger.error "Wasabi upload failed: #{e.message}"
    raise
  end
end
