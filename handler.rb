# frozen_string_literal: true
require 'json'
require 'httparty'
require 'aws-sdk-s3'
require 'aws-sdk-sesv2'

class Mailer
  def self.send_notification(new_jobs)

    heading = <<~EOF
    There are currently #{new_jobs.size} new job(s), they are:

    -------------
    EOF
    jobs = new_jobs.map { |id, job| message(job) }

    formatted_message = heading + jobs.join("\n")

    aws_ses_client.send_email(
      {
        from_email_address: "anthony.s.ross@gmail.com",
        destination: {
          to_addresses: ["anthony.s.ross@gmail.com"],
        },
        content: {
          simple: {
            subject: {
              data: "NEW NETFLIX JOBS!",
            },
            body: {
              text: {
                data: formatted_message
              }
            },
          }
        }
      }
    )
  end

  def self.message(job)
    <<~EOF
      Title: #{job[:text]}
      Team: #{job[:team]&.join(", ")}
      Organiztion: #{job[:organization]&.join(", ")}
      Subteam: #{job[:subteam]&.join(", ")}
      Locations: #{job[:location]}, #{job[:alternate_locations]&.join(", ")}
      Link: https://jobs.netflix.com/jobs/#{job[:external_id]}
      -------------
    EOF
  end

  def self.aws_ses_client
    Aws::SESV2::Client.new
  end
end

class Fetch
  BUCKET = 'ar-jobs'
  KEY = 'netflix_jobs.gz'

  def self.current_listings
    resp = HTTParty.get('https://jobs.netflix.com/api/search?q="engineering manager"', format: :plain)
    jobs = JSON.parse(resp, symbolize_names: true)
    return {} unless jobs.dig(:records, :postings)

    jobs[:records][:postings].map do |job|
      [job[:id].to_sym, job]
    end.to_h
  end

  def self.previous_listings
    if !object_exists?
      put({}) # create it
    end
    get
  end

  def self.object_exists?
    aws_s3_client.head_object(
      bucket: BUCKET,
      key: KEY,
    )
    true
  rescue Aws::S3::Errors::NotFound
    false
  end

  def self.update_previous_listings(new_listings)
    merged_data = previous_listings.merge(new_listings)
    put(merged_data)
    merged_data
  end

  def self.purge_data
    put({})
  end

  def self.put(content)
    zipped = Zlib::Deflate.deflate(JSON.generate(content))
    aws_s3_client.put_object(
      body: zipped,
      bucket: BUCKET,
      key: KEY,
    )
  end

  def self.get(bucket: BUCKET, key: KEY)
    content = aws_s3_client.get_object(bucket: bucket, key: key).body.read
    unzipped = Zlib::Inflate.inflate(content)
    JSON.parse(unzipped, symbolize_names: true)
  end

  def self.aws_s3_client
    Aws::S3::Client.new
  end
end

def return_message(msg, event)
  {
    statusCode: 200,
    body: {
      message: msg,
      input: event
    }.to_json
  }
end

class Runner
  def self.run
    new = Fetch.current_listings
    prev = Fetch.previous_listings
    new_ids = new.keys - prev.keys

    new_jobs = new.select { |k, _v| new_ids.include?(k) }

    Fetch.update_previous_listings(new_jobs)

    msg = "No new jobs"

    if !new_jobs.empty?
      msg = "#{new_jobs.keys.size} new listing(s): #{new_jobs.keys.join(",")}"
      Mailer.send_notification(new_jobs)
    end
    msg
  end
end

def get_jobs(event:, context:)
  if event && event["purge_data"]
    Fetch.purge_data
    return return_message("Purged data", event)
  end

  msg = Runner.run
  return_message(msg, event)
end
