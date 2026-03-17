# frozen_string_literal: true

# Config storage at ~/.config/agentgif/config.json

require "json"
require "fileutils"

module AgentGIF
  module Config
    CONFIG_DIR = File.join(
      ENV.fetch("XDG_CONFIG_HOME", File.join(Dir.home, ".config")),
      "agentgif"
    )
    CONFIG_PATH = File.join(CONFIG_DIR, "config.json")

    module_function

    def load_config
      return {} unless File.exist?(CONFIG_PATH)

      JSON.parse(File.read(CONFIG_PATH))
    rescue JSON::ParserError
      {}
    end

    def save_config(cfg)
      FileUtils.mkdir_p(CONFIG_DIR)
      File.write(CONFIG_PATH, "#{JSON.pretty_generate(cfg)}\n")
    end

    def get_api_key
      load_config["api_key"] || ""
    end

    def save_credentials(api_key, username)
      cfg = load_config
      cfg["api_key"] = api_key
      cfg["username"] = username
      save_config(cfg)
    end

    def clear_credentials
      cfg = load_config
      cfg.delete("api_key")
      cfg.delete("username")
      save_config(cfg)
    end
  end
end
