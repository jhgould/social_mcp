require "rails_helper"
require "tempfile"

RSpec.describe OpenAi::Tools::WhisperTranscriber do
  let(:client) { instance_double(OpenAi::Client) }
  let(:transcriber) { described_class.new(client: client) }

  describe "#call" do
    context "with a local file path" do
      it "uploads the file and returns the transcript text" do
        Tempfile.create([ "audio", ".mp3" ]) do |tempfile|
          tempfile.write("fake audio bytes")
          tempfile.rewind

          expect(client).to receive(:post) do |path, payload:, multipart:|
            expect(path).to eq("/audio/transcriptions")
            expect(multipart).to eq(true)
            expect(payload[:model]).to eq(OpenAi::Tools::WhisperTranscriber::MODEL)
            file, filename = payload[:file]
            expect(file).to respond_to(:read)
            expect(filename).to eq(File.basename(tempfile.path))
            { "text" => "hello from whisper" }
          end

          result = transcriber.call(audio: tempfile.path)

          expect(result).to eq("hello from whisper")
        end
      end
    end

    context "with an already-open file/IO object" do
      it "passes the IO through directly, alongside a fallback filename" do
        io = StringIO.new("fake audio bytes")

        expect(client).to receive(:post)
          .with("/audio/transcriptions", payload: { file: [ io, "audio" ], model: "whisper-1" }, multipart: true)
          .and_return({ "text" => "hello" })

        expect(transcriber.call(audio: io)).to eq("hello")
      end
    end

    context "with a remote URL" do
      let(:remote_url) { "https://cdn.example.com/reel-audio.mp3" }

      it "downloads the file and uploads it with a filename recovered from the URL" do
        stub_request(:get, remote_url).to_return(status: 200, body: "fake audio bytes")

        expect(client).to receive(:post) do |path, payload:, multipart:|
          expect(path).to eq("/audio/transcriptions")
          expect(multipart).to eq(true)
          file, filename = payload[:file]
          expect(file.read).to eq("fake audio bytes")
          expect(filename).to eq("reel-audio.mp3")
          { "text" => "transcribed remote audio" }
        end

        expect(transcriber.call(audio: remote_url)).to eq("transcribed remote audio")
      end
    end

    it "propagates a ResponseError raised by the client" do
      io = StringIO.new("fake audio bytes")
      allow(client).to receive(:post).and_raise(OpenAi::Client::ResponseError.new("bad", status: 500))

      expect { transcriber.call(audio: io) }.to raise_error(OpenAi::Client::ResponseError)
    end

    it "propagates a TimeoutError raised by the client" do
      io = StringIO.new("fake audio bytes")
      allow(client).to receive(:post).and_raise(OpenAi::Client::TimeoutError, "timed out")

      expect { transcriber.call(audio: io) }.to raise_error(OpenAi::Client::TimeoutError)
    end

    it "raises MalformedResponseError when the response is missing 'text'" do
      io = StringIO.new("fake audio bytes")
      allow(client).to receive(:post).and_return({ "unexpected" => true })

      expect { transcriber.call(audio: io) }.to raise_error(OpenAi::Client::MalformedResponseError)
    end
  end
end
