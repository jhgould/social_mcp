require "rails_helper"

RSpec.describe Apify::Tools::TiktokScraper do
  let(:client) { instance_double(Apify::Client) }
  let(:scraper) { described_class.new(client: client) }
  let(:url) { "https://www.tiktok.com/@someone/video/123456" }

  describe "#call" do
    it "returns a Result struct built from the actor's first item on success" do
      item = {
        "text" => "a cool tiktok",
        "videoMeta" => { "downloadAddr" => "https://cdn.example.com/video.mp4" },
        "authorMeta" => { "name" => "some_user" }
      }
      expect(client).to receive(:run_actor_and_fetch_results)
        .with(Apify::Tools::TiktokScraper::ACTOR_ID, input: { postURLs: [ url ] })
        .and_return([ item ])

      result = scraper.call(url: url)

      expect(result.video_url).to eq("https://cdn.example.com/video.mp4")
      expect(result.caption).to eq("a cool tiktok")
      expect(result.author).to eq("some_user")
      expect(result.raw).to eq(item)
    end

    it "propagates a ResponseError raised by the client for a non-200 response" do
      allow(client).to receive(:run_actor_and_fetch_results)
        .and_raise(Apify::Client::ResponseError.new("bad status", status: 503))

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
