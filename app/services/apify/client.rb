require "net/http"
require "json"

module Apify
  # Owns auth, HTTP request/response handling, retries, and error handling
  # for all calls to the Apify REST API. Tool classes (app/services/apify/tools)
  # use this client but never talk HTTP directly.
  class Client
    class Error < StandardError; end
    class TimeoutError < Error; end

    class ResponseError < Error
      attr_reader :status

      def initialize(message, status:)
        @status = status
        super(message)
      end
    end

    class MalformedResponseError < Error; end

    BASE_URL = "https://api.apify.com/v2".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 30
    DEFAULT_POLL_INTERVAL = 2
    DEFAULT_MAX_WAIT = 120
    TERMINAL_STATUSES = %w[SUCCEEDED FAILED TIMED-OUT ABORTED].freeze

    def initialize(api_token: nil)
      @api_token = api_token || self.class.default_api_token
      raise ArgumentError, "Apify API token is missing" if @api_token.blank?
    end

    def run_actor(actor_id, input: {})
      extract_data(request(:post, "/acts/#{actor_id}/runs", body: input))
    end

    def get_run(run_id)
      extract_data(request(:get, "/actor-runs/#{run_id}"))
    end

    def get_dataset_items(dataset_id)
      items = request(:get, "/datasets/#{dataset_id}/items")
      unless items.is_a?(Array)
        raise MalformedResponseError, "Apify dataset #{dataset_id} response was not a list of items"
      end

      items
    end

    # Runs an actor, polls until the run finishes, and returns the resulting
    # dataset items. This is the flow every scraper tool needs, so it lives
    # here once instead of being reimplemented per tool.
    def run_actor_and_fetch_results(actor_id, input: {}, poll_interval: DEFAULT_POLL_INTERVAL, max_wait: DEFAULT_MAX_WAIT)
      run = run_actor(actor_id, input: input)
      run_id = run["id"]
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + max_wait

      until TERMINAL_STATUSES.include?(run["status"])
        if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
          raise Error, "Apify actor run #{run_id} did not finish within #{max_wait}s (last status: #{run['status']})"
        end

        sleep poll_interval
        run = get_run(run_id)
      end

      unless run["status"] == "SUCCEEDED"
        raise Error, "Apify actor run #{run_id} finished with status #{run['status']}"
      end

      dataset_id = run["defaultDatasetId"]
      raise MalformedResponseError, "Apify run #{run_id} response missing defaultDatasetId" if dataset_id.blank?

      get_dataset_items(dataset_id)
    end

    def self.default_api_token
      ENV["APIFY_API_TOKEN"].presence || credentials_api_token
    end

    def self.credentials_api_token
      Rails.application.credentials.dig(:apify, :api_token)
    rescue StandardError
      nil
    end

    private

    def request(method, path, body: nil)
      uri = build_uri(path)
      attempt = 0

      begin
        attempt += 1
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Rails.logger.info("[Apify::Client] request started method=#{method} path=#{path}")

        response = perform_http_request(method, uri, body)

        duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(3)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("[Apify::Client] request failed method=#{method} path=#{path} status=#{response.code} duration=#{duration}")
          raise ResponseError.new(
            "Apify API returned status #{response.code} for #{method.to_s.upcase} #{path}: #{response.body}",
            status: response.code.to_i
          )
        end

        Rails.logger.info("[Apify::Client] request succeeded method=#{method} path=#{path} status=#{response.code} duration=#{duration}")

        parse_json(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        if attempt < 2
          Rails.logger.warn("[Apify::Client] request timed out, retrying method=#{method} path=#{path}")
          retry
        end

        Rails.logger.error("[Apify::Client] request timed out method=#{method} path=#{path}")
        raise TimeoutError, "Apify API request timed out: #{e.message}"
      end
    end

    def build_uri(path)
      uri = URI("#{BASE_URL}#{path}")
      uri.query = URI.encode_www_form(token: @api_token)
      uri
    end

    def perform_http_request(method, uri, body)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = case method
      when :get
        Net::HTTP::Get.new(uri)
      when :post
        Net::HTTP::Post.new(uri).tap do |req|
          req["Content-Type"] = "application/json"
          req.body = (body || {}).to_json
        end
      else
        raise ArgumentError, "Unsupported HTTP method: #{method}"
      end

      http.request(request)
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise MalformedResponseError, "Apify API returned malformed JSON: #{e.message}"
    end

    def extract_data(response)
      unless response.is_a?(Hash) && response.key?("data")
        raise MalformedResponseError, "Apify API response missing 'data' key"
      end

      response["data"]
    end
  end
end
