# frozen_string_literal: true

require "net/http"
require "uri"
require "json"

module LocalCrew
  # Minimal wrapper around Ollama's HTTP API. Never an `ollama`
  # subprocess — everything goes through localhost:11434.
  class OllamaClient
    class Error < StandardError; end

    def initialize(host)
      @host = host
    end

    # GET /api/tags -> { "model_name" => size_in_bytes }
    # On-disk size is a reliable proxy for RAM footprint once the
    # model is loaded.
    def installed_models
      response = get("/api/tags")
      data = JSON.parse(response.body)
      (data["models"] || []).each_with_object({}) do |model, sizes|
        sizes[model["name"]] = model["size"].to_i
      end
    end

    # POST /api/chat (non-streamed) -> parsed response hash.
    def chat(model:, messages:, **options)
      payload = { model: model, messages: messages, stream: false }.merge(options)
      response = post("/api/chat", payload)
      JSON.parse(response.body)
    end

    # POST /api/pull in streamed mode: Ollama returns one JSON line
    # per step ("pulling manifest", "downloading", "success"...).
    # on_progress is called for each one, with the parsed hash —
    # useful to display progress without waiting for the download to
    # finish.
    def pull(model, &on_progress)
      target = uri("/api/pull")
      perform_request do
        request = Net::HTTP::Post.new(target)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(model: model, stream: true)

        http = Net::HTTP.new(target.host, target.port)
        http.read_timeout = nil # a multi-GB model can take a long while

        http.start do |session|
          session.request(request) do |response|
            stream_pull_progress(response, &on_progress)
            response
          end
        end
      end
    end

    private

    def stream_pull_progress(response, &on_progress)
      buffer = +""
      response.read_body do |chunk|
        buffer << chunk
        while (newline_index = buffer.index("\n"))
          handle_pull_progress_line(buffer.slice!(0..newline_index), &on_progress)
        end
      end
      # Ollama (and WebMock in specs) doesn't always end the last
      # line with a newline.
      handle_pull_progress_line(buffer, &on_progress)
    end

    def handle_pull_progress_line(line, &on_progress)
      line = line.strip
      return if line.empty?

      progress = JSON.parse(line)
      raise Error, "Ollama returned an error: #{progress['error']}" if progress["error"]

      on_progress&.call(progress)
    end

    def get(path)
      perform_request { Net::HTTP.get_response(uri(path)) }
    end

    def post(path, payload)
      target = uri(path)
      perform_request do
        request = Net::HTTP::Post.new(target)
        request["Content-Type"] = "application/json"
        request.body = JSON.generate(payload)
        Net::HTTP.start(target.host, target.port) { |http| http.request(request) }
      end
    end

    def uri(path)
      URI.join(@host, path)
    end

    def perform_request
      response = yield
      raise Error, "Ollama responded with HTTP #{response.code} on #{@host}" unless response.is_a?(Net::HTTPSuccess)

      response
    rescue Errno::ECONNREFUSED, SocketError => e
      raise Error, "Could not reach Ollama on #{@host} (#{e.message}). " \
                   "Check that it's running and that ollama_host is correct in the profile."
    end
  end
end
