module Apify
  module Tools
    # Scrapes a single Instagram Reel via the Apify actor, returning a plain
    # struct. Contains no HTTP/auth logic of its own -- all of that lives in
    # Apify::Client.
    class InstagramReelScraper
      ACTOR_ID = "apify~instagram-scraper".freeze

      Result = Struct.new(:video_url, :audio_url, :caption, :author, :raw, keyword_init: true)

      def initialize(client: Apify::Client.new)
        @client = client
      end

      def call(url:)
        items = @client.run_actor_and_fetch_results(ACTOR_ID, input: { directUrls: [ url ] })
        item = items.first

        if item.nil?
          raise Apify::Client::MalformedResponseError, "Instagram reel scraper returned no results for #{url}"
        end

        Result.new(
          video_url: item["videoUrl"],
          audio_url: item["audioUrl"],
          caption: item["caption"],
          author: item["ownerUsername"],
          raw: item
        )
      end
    end
  end
end
