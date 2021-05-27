require 'json'
require 'httparty'
require 'aws-sdk-s3'
require 'aws-sdk-sesv2'

class Mailer
  def self.send_notification(new_jobs)

    heading = "There are currently #{new_jobs.size}, they are:\n\n"
    jobs = new_jobs.map do |job|
      message(job)
    end
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
              data: "NEW NETFLIX JOB!",
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
      -------------
      Title: Technical Project Manager, Network Engineering
      Team: Core Engineering
      Organiztion: Product
      Subteam: Infrastructure Network Engineering
      Locations: Los Angeles, California, Los Gatos, California
      -------------
    EOF
  end

  def self.aws_ses_client
    Aws::SESV2::Client.new
  end
end

class Fetch
  BUCKET = 'ar-jobs'
  KEY = 'netflix_jobs.json'

  def self.current_listings
    resp = HTTParty.get('https://jobs.netflix.com/api/search?q="engineering manager"', format: :plain)
    JSON.parse(resp, symbolize_names: true)
  end

  def self.previous_listings
    s3 = aws_s3_client
    content = s3.get_object(bucket: 'ar-jobs', key: 'netflix_jobs.json').body.read
    JSON.parse(content, symbolize_names: true)
  end

  def self.update_previous_listings(new_listings)
    merged_data = previous_listings.merge(new_listings)
    aws_s3_client.put_object(
      body: JSON.generate(merged_data),
      bucket: BUCKET,
      key: KEY,
    )
    merged_data
  end

  def self.aws_s3_client
    Aws::S3::Client.new
  end
end

class JobDiff
  def self.diff(prev, new)
    prev_ids = get_ids(prev)
    new_ids = get_ids(new)
    new_ids - prev_ids
  end

  def self.get_ids(jobs)
    jobs[:records][:postings].map do |job|
      job[:id]
    end
  end
end

def get_jobs(event:, context:)
  new = Fetch.current_listings
  prev = Fetch.previous_listings
  diff = JobDiff.diff(prev, new)
  diff.each do |id|
    job = new[:records][:postings].find { |job| job[:id] == id }
    Fetch.update_previous_listings(job)
  end

  msg = "No new jobs"

  if !diff.empty?
    msg = "#{diff.size} new listing(s): #{diff.map(&:to_s).join(",")}"
    jobs = new[:records][:postings].select do |job|
      diff.include?(job[:id])
    end

    Mailer.send_notification(jobs)
  end

  {
    statusCode: 200,
    body: {
      message: msg,
      input: event
    }.to_json
  }
end
