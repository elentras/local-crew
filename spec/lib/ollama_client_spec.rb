# frozen_string_literal: true

RSpec.describe LocalCrew::OllamaClient do
  subject(:client) { described_class.new("http://localhost:11434") }

  describe "#installed_models" do
    it "returns installed models with their size in bytes" do
      stub_request(:get, "http://localhost:11434/api/tags")
        .to_return(
          status: 200,
          body: {
            models: [
              { name: "qwen2.5-coder:14b", size: 9_000_000_000 },
              { name: "llama3.1:8b-instruct", size: 5_000_000_000 }
            ]
          }.to_json
        )

      expect(client.installed_models).to eq(
        "qwen2.5-coder:14b" => 9_000_000_000,
        "llama3.1:8b-instruct" => 5_000_000_000
      )
    end

    it "raises a clear error when Ollama is unreachable" do
      stub_request(:get, "http://localhost:11434/api/tags").to_raise(Errno::ECONNREFUSED)

      expect { client.installed_models }
        .to raise_error(described_class::Error, /Could not reach Ollama/)
    end

    it "raises a clear error on HTTP failure" do
      stub_request(:get, "http://localhost:11434/api/tags").to_return(status: 500, body: "")

      expect { client.installed_models }
        .to raise_error(described_class::Error, /HTTP 500/)
    end
  end

  describe "#chat" do
    it "posts to /api/chat and returns the parsed response" do
      stub_request(:post, "http://localhost:11434/api/chat")
        .with(body: hash_including("model" => "qwen2.5-coder:14b", "stream" => false))
        .to_return(status: 200, body: { message: { content: "ok" } }.to_json)

      response = client.chat(model: "qwen2.5-coder:14b", messages: [{ role: "user", content: "hi" }])

      expect(response.dig("message", "content")).to eq("ok")
    end
  end

  describe "#pull" do
    it "yields each streamed progress step" do
      stub_request(:post, "http://localhost:11434/api/pull")
        .with(body: hash_including("model" => "qwen2.5-coder:14b", "stream" => true))
        .to_return(
          status: 200,
          body: [
            { status: "pulling manifest" }.to_json,
            { status: "downloading", total: 100, completed: 50 }.to_json,
            { status: "success" }.to_json
          ].join("\n")
        )

      progress_steps = []
      client.pull("qwen2.5-coder:14b") { |progress| progress_steps << progress["status"] }

      expect(progress_steps).to eq(["pulling manifest", "downloading", "success"])
    end

    it "raises when Ollama reports an error mid-stream" do
      stub_request(:post, "http://localhost:11434/api/pull")
        .to_return(status: 200, body: { error: "pull model manifest: file does not exist" }.to_json)

      expect { client.pull("ghost-model") { |_progress| nil } }
        .to raise_error(described_class::Error, /Ollama returned an error/)
    end
  end
end
