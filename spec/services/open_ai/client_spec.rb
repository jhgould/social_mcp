require "rails_helper"

RSpec.describe OpenAi::Client do
  let(:api_key) { "test-openai-key" }
  let(:client) { described_class.new(api_key: api_key) }
  let(:url) { "https://api.openai.com/v1/audio/transcriptions" }

  describe "#initialize" do
    it "raises when no key is available" do
      allow(described_class).to receive(:default_api_key).and_return(nil)
      expect { described_class.new }.to raise_error(ArgumentError, /key is missing/)
    end
  end

  describe "#post" do
    it "returns the parsed JSON body on a successful response" do
      stub_request(:post, url).to_return(
        status: 200,
        body: { text: "hello world" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

      result = client.post("/audio/transcriptions", payload: { model: "whisper-1" })

      expect(result).to eq("text" => "hello world")
    end

    it "sends the API key as a bearer token and never in the body" do
      stub_request(:post, url).to_return(status: 200, body: { text: "hi" }.to_json)

      client.post("/audio/transcriptions", payload: { model: "whisper-1" })

      expect(WebMock).to have_requested(:post, url)
        .with(headers: { "Authorization" => "Bearer #{api_key}" })
    end

    it "does not leak the API key in logs" do
      stub_request(:post, url).to_return(status: 200, body: { text: "hi" }.to_json)

      logged_messages = []
      allow(Rails.logger).to receive(:info) { |msg| logged_messages << msg }

      client.post("/audio/transcriptions", payload: { model: "whisper-1" })

      expect(logged_messages).not_to be_empty
      expect(logged_messages.join).not_to include(api_key)
    end

    it "raises ResponseError on a non-200 response" do
      stub_request(:post, url).to_return(status: 401, body: "unauthorized")

      expect { client.post("/audio/transcriptions", payload: {}) }
        .to raise_error(OpenAi::Client::ResponseError) { |error| expect(error.status).to eq(401) }
    end

    it "raises TimeoutError after one retry on timeout" do
      stub_request(:post, url).to_timeout

      expect { client.post("/audio/transcriptions", payload: {}) }.to raise_error(OpenAi::Client::TimeoutError)
      expect(WebMock).to have_requested(:post, url).times(2)
    end

    it "raises MalformedResponseError on invalid JSON" do
      stub_request(:post, url).to_return(status: 200, body: "not json")

      expect { client.post("/audio/transcriptions", payload: {}) }
        .to raise_error(OpenAi::Client::MalformedResponseError)
    end

    it "supports multipart payloads for file uploads" do
      stub_request(:post, url).to_return(status: 200, body: { text: "hi" }.to_json)

      file = StringIO.new("fake audio bytes")
      def file.original_filename; "audio.mp3"; end

      result = client.post("/audio/transcriptions", payload: { file: file, model: "whisper-1" }, multipart: true)

      expect(result).to eq("text" => "hi")
      expect(WebMock).to have_requested(:post, url)
        .with { |req| req.headers["Content-Type"].to_s.start_with?("multipart/form-data") }
    end

    it "uses an explicit [io, filename] pair to name the uploaded part" do
      stub_request(:post, url).to_return(status: 200, body: { text: "hi" }.to_json)

      file = StringIO.new("fake audio bytes")

      client.post("/audio/transcriptions", payload: { file: [ file, "reel-audio.mp3" ], model: "whisper-1" }, multipart: true)

      expect(WebMock).to have_requested(:post, url)
        .with { |req| req.body.include?('filename="reel-audio.mp3"') }
    end
  end
end
