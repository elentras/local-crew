# frozen_string_literal: true

RSpec.describe LocalCrew::RamEstimator do
  let(:gb) { 1024**3 }
  let(:profile) { { "available_for_models_gb" => 20, "max_concurrent_models" => 2 } }
  let(:role_bindings) do
    {
      "backend_dev" => { "model" => "qwen2.5-coder:14b", "keep_alive" => -1 },
      "qa" => { "model" => "llama3.1:8b-instruct", "keep_alive" => "30m" }
    }
  end
  let(:installed_models) do
    {
      "qwen2.5-coder:14b" => 9 * gb,
      "llama3.1:8b-instruct" => 5 * gb
    }
  end

  subject(:estimator) do
    described_class.new(profile: profile, role_bindings: role_bindings, installed_models: installed_models)
  end

  it "passes when models exist and RAM fits comfortably" do
    result = estimator.estimate!

    expect(result.total_persistent_gb).to be_within(0.01).of(14.0)
    expect(result.persistent_roles.sort).to eq(%w[backend_dev qa])
    expect(result.warnings).to be_empty
  end

  it "fails when a model is missing from Ollama" do
    installed_models.delete("llama3.1:8b-instruct")

    expect { estimator.estimate! }
      .to raise_error(described_class::Error, /qa.*llama3\.1:8b-instruct.*not found/)
  end

  it "fails when persistent RAM exceeds the available budget" do
    profile["available_for_models_gb"] = 10

    expect { estimator.estimate! }
      .to raise_error(described_class::Error, /exceeds available_for_models_gb/)
  end

  it "fails when persistent model count exceeds max_concurrent_models" do
    profile["max_concurrent_models"] = 1

    expect { estimator.estimate! }
      .to raise_error(described_class::Error, /max_concurrent_models allows 1/)
  end

  it "excludes transient keep_alive from the RAM sum" do
    role_bindings["qa"]["keep_alive"] = "30s"

    result = estimator.estimate!

    expect(result.total_persistent_gb).to be_within(0.01).of(9.0)
    expect(result.persistent_roles).to eq(["backend_dev"])
  end

  it "warns without failing when the margin is under 10%" do
    profile["available_for_models_gb"] = 14.5

    result = estimator.estimate!

    expect(result.warnings.first).to match(/RAM margin < 10%/)
  end
end
