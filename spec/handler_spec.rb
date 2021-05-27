require 'spec_helper'

describe "get_jobs" do
  let(:previous_jobs) do
    JSON.parse(File.read("./spec/jobs.json"), symbolize_names: true)
  end
  let(:response) do
    JSON.parse(get_jobs(event: nil, context: nil)[:body], symbolize_names: true)
  end

  it "compares new jobs to old jobs and has no output when they are the same" do
    allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
    allow(Fetch).to receive(:current_listings).and_return(previous_jobs)
    resp = response
    expect(resp[:message]).to eq("No new jobs")
  end

  it "compares new jobs to old jobs and has no output when they are the same" do
    new_jobs = JSON.parse(File.read("./spec/jobs_fake.json"), symbolize_names: true)
    allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
    allow(Fetch).to receive(:current_listings).and_return(new_jobs)
    resp = response
    expect(resp[:message]).to eq("1 new listing(s): 9999")
  end

  it "saves any new listings into the previous listing" do
    new_jobs = JSON.parse(File.read("./spec/jobs_fake.json"), symbolize_names: true)
    allow(Fetch).to receive(:previous_listings).and_return(previous_jobs)
    allow(Fetch).to receive(:current_listings).and_return(new_jobs)
    expect(Fetch).to receive(:update_previous_listings).with(hash_including(external_id: "9999"))

    response
  end

  it "saves any new listings into the previous listing" do
  end

  describe "Fetch" do
    context "current_listings" do
      it "makes a call to Netflix" do
        expect(JSON).to receive(:parse).with({}, symbolize_names: true)
        expect(HTTParty).to receive(:get).with('https://jobs.netflix.com/api/search?q="engineering manager"', format: :plain).and_return({})
        Fetch.current_listings
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

end
