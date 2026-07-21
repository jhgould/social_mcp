require "open-uri"

module OpenAi
  module Tools
    # Transcribes an audio file (local path, File/IO, or remote URL) using
    # OpenAI's Whisper model. Contains no HTTP/auth logic of its own -- all
    # of that lives in OpenAi::Client.
    class WhisperTranscriber
      MODEL = "whisper-1".freeze

      def initialize(client: OpenAi::Client.new)
        @client = client
      end

      def call(audio:)
        with_audio_file(audio) do |file, filename|
          response = @client.post(
            "/audio/transcriptions",
            payload: { file: [ file, filename ], model: MODEL },
            multipart: true
          )

          extract_text(response)
        end
      end

      private

      def with_audio_file(audio)
        if remote_url?(audio)
          downloaded = URI.parse(audio).open
          begin
            yield downloaded, remote_filename(audio)
          ensure
            downloaded.close
          end
        elsif audio.respond_to?(:read)
          filename = audio.respond_to?(:path) && audio.path ? File.basename(audio.path) : "audio"
          yield audio, filename
        else
          File.open(audio, "rb") { |file| yield file, File.basename(audio) }
        end
      end

      def remote_url?(audio)
        audio.is_a?(String) && audio.start_with?("http://", "https://")
      end

      # Downloaded remote files land in a Tempfile whose path has no real
      # extension, so Whisper (which sniffs the upload's filename to detect
      # format) needs the extension recovered from the source URL instead.
      def remote_filename(url)
        name = File.basename(URI.parse(url).path)
        name.present? ? name : "audio.mp3"
      end

      def extract_text(response)
        text = response["text"]
        raise OpenAi::Client::MalformedResponseError, "OpenAI transcription response missing 'text'" if text.nil?

        text
      end
    end
  end
end
