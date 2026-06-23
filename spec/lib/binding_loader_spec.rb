# frozen_string_literal: true

RSpec.describe LocalCrew::BindingLoader do
  let(:root) { File.expand_path("../fixtures", __dir__) }

  subject(:loader) { described_class.new(root: root, profile_name: "test-profile") }

  describe "#profile" do
    it "loads the profile YAML" do
      expect(loader.profile["available_for_models_gb"]).to eq(28)
    end

    it "raises when the profile file is missing" do
      missing = described_class.new(root: root, profile_name: "does-not-exist")

      expect { missing.profile }.to raise_error(described_class::Error, /not found/)
    end
  end

  describe "#role_bindings" do
    it "loads and validates the binding against the schema" do
      expect(loader.role_bindings.keys).to contain_exactly("backend_dev", "qa")
    end

    it "raises when the binding violates the schema" do
      invalid = described_class.new(root: root, profile_name: "invalid-profile")

      expect { invalid.role_bindings }.to raise_error(described_class::Error, /invalid/)
    end
  end

  describe "#for_role" do
    it "returns the resolved config for a known role" do
      config = loader.for_role("backend_dev")

      expect(config).to include("role" => "backend_dev", "model" => "qwen2.5-coder:14b")
    end

    it "raises when the role is absent from the binding" do
      expect { loader.for_role("ghost") }.to raise_error(described_class::Error, /absent/)
    end
  end
end
