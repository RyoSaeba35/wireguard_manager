class BackupDatabaseJob < ApplicationJob
  queue_as :default

  def perform(*args)
    # Parse DATABASE_URL for connection details
    db_url = URI.parse(ENV['DATABASE_URL'])
    db_host = db_url.host
    db_port = db_url.port
    db_user = db_url.user
    db_password = db_url.password
    db_name = db_url.path.gsub('/', '')

    # Define the backup filename with a timestamp
    backup_file = "railway_backup_#{Time.now.strftime('%Y%m%d_%H%M%S')}.sql"

    # Dump the database to a temporary file
    `PGPASSWORD="#{db_password}" pg_dump -h #{db_host} -p #{db_port} -U #{db_user} -d #{db_name} -F c -f /tmp/#{backup_file}`

    # Upload the backup to Wasabi using existing AWS config vars
    `aws s3 cp "/tmp/#{backup_file}" "s3://#{ENV['AWS_BUCKET']}/#{backup_file}" --endpoint=#{ENV['AWS_ENDPOINT']} --region=#{ENV['AWS_REGION']}`

    # Remove the temporary file
    `rm "/tmp/#{backup_file}"`
  end
end
