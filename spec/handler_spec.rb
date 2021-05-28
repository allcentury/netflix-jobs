require 'spec_helper'

describe "get_jobs" do
  let(:new_jobs) do
    new_jobs = JSON.parse(File.read("./spec/jobs_fake.json"), symbolize_names: true)
    new_jobs = new_jobs[:records][:postings].map do |job|
      [job[:id], job]
    end.to_h
  end

  context "handler tests" do
    before(:each) do
      allow(Mailer).to receive(:send_notification)
    end
    let(:previous_jobs) do
      jobs = JSON.parse(File.read("./spec/jobs.json"), symbolize_names: true)
      jobs[:records][:postings].map do |job|
        [job[:id], job]
      end.to_h
    end
    let(:response) do
      JSON.parse(get_jobs(event: nil, context: nil)[:body], symbolize_names: true)
    end

    it "compares new jobs to old jobs and has no output when they are the same" do
      allow(HTTParty).to receive(:get).with('https://jobs.netflix.com/api/search?q="engineering manager"', format: :plain).and_return(File.read('./spec/jobs.json'))
      allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
      resp = response
      expect(resp[:message]).to eq("No new jobs")
    end

    it "loads for the first time" do
      allow(Fetch).to receive(:previous_listings).and_return({})
      allow(Fetch).to receive(:current_listings).and_return(previous_jobs)
      resp = response
      expect(resp[:message]).to include("20 new listing(s)")
    end

    it "compares new jobs to old jobs and outputs the id of hte new listing" do
      allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
      allow(Fetch).to receive(:current_listings).and_return(new_jobs)
      resp = response
      expect(resp[:message]).to eq("1 new listing(s): 9999")
    end

    it "saves any new listings into the previous listing" do
      allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
      allow(Fetch).to receive(:current_listings).and_return(new_jobs).once
      expect(Fetch).to receive(:put) do |arg|
        expect(arg.keys.size).to eq(21)
        expect(arg["9999"]).to be_truthy
      end

      response
    end

    it "compares new jobs to old jobs and has no output when they are the same" do
      allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
      allow(Fetch).to receive(:current_listings).and_return(new_jobs)
      resp = response
      expect(resp[:message]).to eq("1 new listing(s): 9999")
    end

    it "saves any new listings into the previous listing" do
      allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
      allow(Fetch).to receive(:current_listings).and_return(new_jobs)
      expect(Fetch).to receive(:update_previous_listings) do |arg|
        expect(arg["9999"]).to be_truthy
      end

      response
    end

    it "emails on new listings" do
      allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
      allow(Fetch).to receive(:current_listings).and_return(new_jobs)
      expect(Mailer).to receive(:send_notification) do |jobs|
        expect(jobs["9999"]).to be_truthy
      end

      response
    end
  end

  describe "Fetch" do
    context "current_listings" do
      it "makes a call to Netflix" do
        expect(JSON).to receive(:parse).with("{}", symbolize_names: true).and_call_original
        expect(HTTParty).to receive(:get).with('https://jobs.netflix.com/api/search?q="engineering manager"', format: :plain).and_return("{}")
        Fetch.current_listings
      end

      it "returns a hash with id as the key and the job as the payload" do
        expect(HTTParty).to receive(:get).with('https://jobs.netflix.com/api/search?q="engineering manager"', format: :plain).and_return(File.read('./spec/jobs.json'))
        jobs = Fetch.current_listings
        expect(jobs.keys.length).to eq(20)
      end
    end

    context "previous_listings" do
      it "calls S3" do
        body = "{}"
        stub = Aws::S3::Client.new(stub_responses: {
          get_object: { body: body }
        })
        allow(Fetch).to receive(:aws_s3_client).and_return(stub)

        response = Fetch.previous_listings
        expect(response).to eq({})
      end
    end

    context "update_listings" do
      it "updates with new data" do
        old_job = { c: :d }
        new_job = { a: :b }
        merged_data = old_job.merge(new_job)
        stub = Aws::S3::Client.new(stub_responses: true)
        expect(Fetch).to receive(:previous_listings).and_return(old_job)
        allow(Fetch).to receive(:aws_s3_client).and_return(stub)
        expect(stub).to receive(:put_object).with(body: JSON.generate(merged_data), bucket: 'ar-jobs', key: 'netflix_jobs.json').and_call_original

        merged_data = Fetch.update_previous_listings(new_job)
        expect(merged_data).to eq(merged_data)
      end
    end
  end

  describe "Mailer" do
    it "sends email via SES" do
      stub = Aws::SESV2::Client.new(stub_responses: true)
      allow(Mailer).to receive(:aws_ses_client).and_return(stub)
      message = <<~EOF
      There are currently #{new_jobs.size} new job(s), they are:

      -------------
      Title: Technical Project Manager, Network Engineering
      Team: Core Engineering
      Organiztion: Product
      Subteam: Infrastructure Network Engineering
      Locations: Los Angeles, California, Los Gatos, California
      Link: https://jobs.netflix.com/jobs/9999
      -------------
      EOF

      args = {
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
                data: message
              }
            },
          }
        }
      }
      expect(stub).to receive(:send_email).with(args).and_call_original

      Mailer.send_notification(new_jobs)
    end
  end
end
