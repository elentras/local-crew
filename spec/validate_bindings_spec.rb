# frozen_string_literal: true

require_relative "../.ai/scripts/validate_bindings"

RSpec.describe LocalCrew::CLI do
  let(:fixtures_root) { File.expand_path("fixtures", __dir__) }

  it "loads profile and binding by name and validates them" do
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

    result = described_class.run(["test-profile"], root: fixtures_root)

    expect(result.total_persistent_gb).to be_within(0.01).of(14.0)
  end

  it "falls back to config.yml's profile when none is given" do
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

    result = described_class.run([], root: fixtures_root)

    expect(result.total_persistent_gb).to be_within(0.01).of(14.0)
  end

  it "raises when no profile name is given and config.yml declares none" do
    Dir.mktmpdir do |empty_root|
      expect { described_class.run([], root: empty_root) }
        .to raise_error(LocalCrew::BindingLoader::Error, /Usage/)
    end
  end
end
