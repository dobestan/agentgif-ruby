# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = "agentgif"
  s.version     = "0.2.0"
  s.summary     = "CLI for AgentGIF — upload, manage, and share terminal GIFs"
  s.description = "Upload, search, and manage terminal demo GIFs on AgentGIF.com. " \
                  "Generate terminal-themed package badges."
  s.authors     = ["AgentGIF"]
  s.email       = ["hello@agentgif.com"]
  s.homepage    = "https://agentgif.com"
  s.license     = "MIT"
  s.metadata    = {
    "source_code_uri" => "https://github.com/dobestan/agentgif-ruby",
    "bug_tracker_uri" => "https://github.com/dobestan/agentgif-ruby/issues",
    "documentation_uri" => "https://agentgif.com/docs/cli/"
  }

  s.required_ruby_version = ">= 3.0"

  s.executables = ["agentgif"]
  s.files       = Dir["lib/**/*.rb", "bin/*"]

  s.add_dependency "json"
end
