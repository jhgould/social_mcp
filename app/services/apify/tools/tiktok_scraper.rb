module Apify
  module Tools
    # Scrapes a single TikTok video via the Apify actor, returning a plain
    # struct. Contains no HTTP/auth logic of its own -- all of that lives in
    # Apify::Client.
    class TiktokScraper
      ACTOR_ID = "clockworks~tiktok-scraper".freeze

      Result = Struct.new(:video_url, :caption, :author, :raw, keyword_init: true)

      def initialize(client: Apify::Client.new)
        @client = client
      end

      def call(url:)
        items = @client.run_actor_and_fetch_results(ACTOR_ID, input: { postURLs: [ url ] })
        item = items.first

        if item.nil?
          raise Apify::Client::MalformedResponseError, "TikTok scraper returned no results for #{url}"
        end

        Result.new(
          video_url: item.dig("videoMeta", "downloadAddr"),
          caption: item["text"],
          author: item.dig("authorMeta", "name"),
          raw: item
        )
      end
    end
  end
end
