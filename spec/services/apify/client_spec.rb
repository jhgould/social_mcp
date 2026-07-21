require "rails_helper"

RSpec.describe Apify::Client do
  let(:token) { "test-apify-token" }
  let(:client) { described_class.new(api_token: token) }

  describe "#initialize" do
    it "raises when no token is available" do
      allow(described_class).to receive(:default_api_token).and_return(nil)
      expect { described_class.new }.to raise_error(ArgumentError, /token is missing/)
    end
  end

  describe "#run_actor" do
    let(:actor_id) { "apify/instagram-reel-scraper" }
    let(:url) { %r{\Ahttps://api\.apify\.com/v2/acts/apify/instagram-reel-scraper/runs} }

    it "returns the run data on a successful response" do
      stub_request(:post, url).to_return(
        status: 201,
        body: { data: { id: "run123", status: "READY" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = client.run_actor(actor_id, input: { directUrls: [ "https://instagram.com/reel/abc" ] })

      expect(result).to eq("id" => "run123", "status" => "READY")
    end

    it "does not leak the token in logs" do
      stub_request(:post, url).to_return(
        status: 201,
        body: { data: { id: "run123", status: "READY" } }.to_json
      )

      logged_messages = []
      allow(Rails.logger).to receive(:info) { |msg| logged_messages << msg }

      client.run_actor(actor_id, input: {})

      expect(logged_messages).not_to be_empty
      expect(logged_messages.join).not_to include(token)
    end

    it "raises ResponseError on a non-200 response" do
      stub_request(:post, url).to_return(status: 500, body: "internal error")

      expect { client.run_actor(actor_id, input: {}) }
        .to raise_error(Apify::Client::ResponseError) { |error| expect(error.status).to eq(500) }
    end

    it "raises TimeoutError after one retry on timeout" do
      stub_request(:post, url).to_timeout

      expect { client.run_actor(actor_id, input: {}) }.to raise_error(Apify::Client::TimeoutError)
      expect(WebMock).to have_requested(:post, url).times(2)
    end

    it "raises MalformedResponseError on invalid JSON" do
      stub_request(:post, url).to_return(status: 201, body: "not json")

      expect { client.run_actor(actor_id, input: {}) }
        .to raise_error(Apify::Client::MalformedResponseError)
    end

    it "raises MalformedResponseError when the 'data' key is missing" do
      stub_request(:post, url).to_return(status: 201, body: { unexpected: true }.to_json)

      expect { client.run_actor(actor_id, input: {}) }
        .to raise_error(Apify::Client::MalformedResponseError)
    end
  end

  describe "#get_run" do
    let(:run_id) { "run123" }
    let(:url) { "https://api.apify.com/v2/actor-runs/#{run_id}" }

    it "returns the run data" do
      stub_request(:get, url).with(query: hash_including("token" => token)).to_return(
        status: 200,
        body: { data: { id: run_id, status: "SUCCEEDED" } }.to_json
      )

      expect(client.get_run(run_id)).to eq("id" => run_id, "status" => "SUCCEEDED")
    end

    it "raises ResponseError on a non-200 response" do
      stub_request(:get, url).with(query: hash_including("token" => token)).to_return(status: 404, body: "not found")

      expect { client.get_run(run_id) }.to raise_error(Apify::Client::ResponseError)
    end
  end

  describe "#get_dataset_items" do
    let(:dataset_id) { "dataset123" }
    let(:url) { "https://api.apify.com/v2/datasets/#{dataset_id}/items" }

    it "returns the list of items" do
      stub_request(:get, url).with(query: hash_including("token" => token)).to_return(
        status: 200,
        body: [ { "videoUrl" => "https://example.com/video.mp4" } ].to_json
      )

      expect(client.get_dataset_items(dataset_id)).to eq([ { "videoUrl" => "https://example.com/video.mp4" } ])
    end

    it "raises MalformedResponseError when the response is not a list" do
      stub_request(:get, url).with(query: hash_including("token" => token)).to_return(
        status: 200,
        body: { unexpected: "hash" }.to_json
      )

      expect { client.get_dataset_items(dataset_id) }.to raise_error(Apify::Client::MalformedResponseError)
    end
  end

  describe "#run_actor_and_fetch_results" do
    let(:actor_id) { "apify/instagram-reel-scraper" }
    let(:run_id) { "run123" }
    let(:dataset_id) { "dataset123" }

    it "runs the actor, polls until finished, and returns dataset items" do
      stub_request(:post, %r{/v2/acts/.*/runs}).to_return(
        status: 201,
        body: { data: { id: run_id, status: "RUNNING" } }.to_json
      )
      stub_request(:get, "https://api.apify.com/v2/actor-runs/#{run_id}").to_return(
        status: 200,
        body: { data: { id: run_id, status: "SUCCEEDED", defaultDatasetId: dataset_id } }.to_json
      )
      stub_request(:get, "https://api.apify.com/v2/datasets/#{dataset_id}/items").to_return(
        status: 200,
        body: [ { "videoUrl" => "https://example.com/video.mp4" } ].to_json
      )

      items = client.run_actor_and_fetch_results(actor_id, input: {}, poll_interval: 0)

      expect(items).to eq([ { "videoUrl" => "https://example.com/video.mp4" } ])
    end

    it "raises an Error when the run fails" do
      stub_request(:post, %r{/v2/acts/.*/runs}).to_return(
        status: 201,
        body: { data: { id: run_id, status: "RUNNING" } }.to_json
      )
      stub_request(:get, "https://api.apify.com/v2/actor-runs/#{run_id}").to_return(
        status: 200,
        body: { data: { id: run_id, status: "FAILED" } }.to_json
      )

      expect { client.run_actor_and_fetch_results(actor_id, input: {}, poll_interval: 0) }
        .to raise_error(Apify::Client::Error, /finished with status FAILED/)
    end
  end
end
