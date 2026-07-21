require "rails_helper"

RSpec.describe Apify::Tools::InstagramReelScraper do
  let(:client) { instance_double(Apify::Client) }
  let(:scraper) { described_class.new(client: client) }
  let(:url) { "https://www.instagram.com/reel/abc123/" }

  describe "#call" do
    it "returns a Result struct built from the actor's first item on success" do
      item = {
        "videoUrl" => "https://cdn.example.com/video.mp4",
        "audioUrl" => "https://cdn.example.com/audio.mp4",
        "caption" => "a cool reel",
        "ownerUsername" => "some_user"
      }
      expect(client).to receive(:run_actor_and_fetch_results)
        .with(Apify::Tools::InstagramReelScraper::ACTOR_ID, input: { directUrls: [ url ] })
        .and_return([ item ])

      result = scraper.call(url: url)

      expect(result.video_url).to eq("https://cdn.example.com/video.mp4")
      expect(result.audio_url).to eq("https://cdn.example.com/audio.mp4")
      expect(result.caption).to eq("a cool reel")
      expect(result.author).to eq("some_user")
      expect(result.raw).to eq(item)
    end

    it "propagates a ResponseError raised by the client for a non-200 response" do
      allow(client).to receive(:run_actor_and_fetch_results)
        .and_raise(Apify::Client::ResponseError.new("bad status", status: 500))

      expect { scraper.call(url: url) }.to raise_error(Apify::Client::ResponseError)
    end

    it "propagates a TimeoutError raised by the client" do
      allow(client).to receive(:run_actor_and_fetch_results).and_raise(Apify::Client::TimeoutError, "timed out")

      expect { scraper.call(url: url) }.to raise_error(Apify::Client::TimeoutError)
    end

    it "raises MalformedResponseError when the actor returns no items" do
      allow(client).to receive(:run_actor_and_fetch_results).and_return([])

      expect { scraper.call(url: url) }.to raise_error(Apify::Client::MalformedResponseError)
    end
  end
end
