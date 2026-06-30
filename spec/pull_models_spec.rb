# frozen_string_literal: true

require_relative "../.ai/scripts/pull_models"

RSpec.describe LocalCrew::PullModels do
  let(:fixtures_root) { File.expand_path("fixtures", __dir__) }

  it "only pulls models from the binding that aren't already installed" do
    stub_request(:get, "http://localhost:11434/api/tags")
      .to_return(
        status: 200,
        body: { models: [{ name: "qwen2.5-coder:14b", size: 9 * (1024**3) }] }.to_json
      )
    pull_stub = stub_request(:post, "http://localhost:11434/api/pull")
      .with(body: hash_including("model" => "llama3.1:8b-instruct"))
      .to_return(status: 200, body: { status: "success" }.to_json)

    pulled = described_class.run(["test-profile"], root: fixtures_root)

    expect(pulled).to eq(["llama3.1:8b-instruct"])
    expect(pull_stub).to have_been_requested
  end

  it "pulls nothing when every model is already installed" do
    stub_request(:get, "http://localhost:11434/api/tags")
      .to_return(
        status: 200,
        body: {
          models: [
            { name: "qwen2.5-coder:14b", size: 9 * (1024**3) },
            { name: "llama3.1:8b-instruct", size: 5 * (1024**3) }
          ]
        }.to_json
      )

    pulled = described_class.run(["test-profile"], root: fixtures_root)

    expect(pulled).to be_empty
  end

  it "falls back to config.yml's profile when none is given" do
    stub_request(:get, "http://localhost:11434/api/tags")
      .to_return(
        status: 200,
        body: { models: [{ name: "qwen2.5-coder:14b", size: 9 * (1024**3) }] }.to_json
      )
    pull_stub = stub_request(:post, "http://localhost:11434/api/pull")
      .with(body: hash_including("model" => "llama3.1:8b-instruct"))
      .to_return(status: 200, body: { status: "success" }.to_json)

    pulled = described_class.run([], root: fixtures_root)

    expect(pulled).to eq(["llama3.1:8b-instruct"])
    expect(pull_stub).to have_been_requested
  end

  it "raises when no profile name is given and config.yml declares none" do
    Dir.mktmpdir do |empty_root|
      expect { described_class.run([], root: empty_root) }
        .to raise_error(LocalCrew::BindingLoader::Error, /Usage/)
    end
  end
end
