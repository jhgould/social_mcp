require "net/http"
require "json"

module OpenAi
  # Owns auth, HTTP request/response handling, retries, and error handling
  # for all calls to the OpenAI API. Tool classes (app/services/open_ai/tools)
  # use `post` but never talk HTTP directly.
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

    BASE_URL = "https://api.openai.com/v1".freeze
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 120

    def initialize(api_key: nil)
      @api_key = api_key || self.class.default_api_key
      raise ArgumentError, "OpenAI API key is missing" if @api_key.blank?
    end

    # Generic POST used by every tool. `payload` is a Hash; pass
    # multipart: true when it contains a file (e.g. audio uploads), which
    # sends it as multipart/form-data instead of JSON.
    def post(path, payload: {}, multipart: false)
      uri = URI("#{BASE_URL}#{path}")
      attempt = 0

      begin
        attempt += 1
        started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        Rails.logger.info("[OpenAi::Client] request started method=POST path=#{path}")

        response = perform_http_request(uri, payload, multipart)

        duration = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(3)

        unless response.is_a?(Net::HTTPSuccess)
          Rails.logger.warn("[OpenAi::Client] request failed method=POST path=#{path} status=#{response.code} duration=#{duration}")
          raise ResponseError.new(
            "OpenAI API returned status #{response.code} for POST #{path}: #{response.body}",
            status: response.code.to_i
          )
        end

        Rails.logger.info("[OpenAi::Client] request succeeded method=POST path=#{path} status=#{response.code} duration=#{duration}")

        parse_json(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout, Timeout::Error => e
        if attempt < 2
          Rails.logger.warn("[OpenAi::Client] request timed out, retrying method=POST path=#{path}")
          retry
        end

        Rails.logger.error("[OpenAi::Client] request timed out method=POST path=#{path}")
        raise TimeoutError, "OpenAI API request timed out: #{e.message}"
      end
    end

    def self.default_api_key
      ENV["OPENAI_API_KEY"].presence || credentials_api_key
    end

    def self.credentials_api_key
      Rails.application.credentials.dig(:open_ai, :api_key)
    rescue StandardError
      nil
    end

    private

    def perform_http_request(uri, payload, multipart)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = OPEN_TIMEOUT
      http.read_timeout = READ_TIMEOUT

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"

      if multipart
        request.set_form(build_multipart_fields(payload), "multipart/form-data")
      else
        request["Content-Type"] = "application/json"
        request.body = payload.to_json
      end

      http.request(request)
    end

    # Payload values are normally scalars, but a file to upload may be given
    # as [io, filename] (or a plain IO/File) -- OpenAI requires the part's
    # filename to carry a real audio/video extension so it can detect format.
    def build_multipart_fields(payload)
      payload.map do |key, value|
        io, filename = value.is_a?(Array) ? value : [ value, nil ]

        if io.respond_to?(:read)
          filename ||= (io.respond_to?(:original_filename) && io.original_filename) ||
                       (io.respond_to?(:path) && io.path && File.basename(io.path)) ||
                       key.to_s
          [ key.to_s, io, { filename: filename } ]
        else
          [ key.to_s, io ]
        end
      end
    end

    def parse_json(body)
      JSON.parse(body)
    rescue JSON::ParserError => e
      raise MalformedResponseError, "OpenAI API returned malformed JSON: #{e.message}"
    end
  end
end
