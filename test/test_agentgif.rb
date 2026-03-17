# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/agentgif/cli"
require_relative "../lib/agentgif/config"
require_relative "../lib/agentgif/client"

class TestAgentGIF < Minitest::Test
  def test_version
    assert_match(/\d+\.\d+\.\d+/, AgentGIF::VERSION)
  end

  def test_version_is_0_2_0
    assert_equal "0.2.0", AgentGIF::VERSION
  end

  def test_base_url
    assert_equal "https://agentgif.com", AgentGIF::Client::BASE_URL
  end

  def test_parse_opts_value_flags
    result = AgentGIF::CLI.send(:parse_opts,
                                ["-t", "My Title", "file.gif"],
                                %w[-t --title],
                                [])
    assert_equal "My Title", result["-t"]
    assert_equal ["file.gif"], result[:positional]
  end

  def test_parse_opts_bool_flags
    result = AgentGIF::CLI.send(:parse_opts,
                                ["file.gif", "--yes"],
                                [],
                                %w[-y --yes])
    assert_equal true, result["--yes"]
    assert_equal ["file.gif"], result[:positional]
  end

  def test_parse_opts_mixed
    result = AgentGIF::CLI.send(:parse_opts,
                                ["-t", "Title", "--unlisted", "demo.gif", "--tags", "a,b"],
                                %w[-t --title --tags],
                                %w[--unlisted])
    assert_equal "Title", result["-t"]
    assert_equal "a,b", result["--tags"]
    assert_equal true, result["--unlisted"]
    assert_equal ["demo.gif"], result[:positional]
  end

  def test_detect_repo_nil_when_not_git
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        result = AgentGIF::CLI.send(:detect_repo)
        assert_nil result
      end
    end
  end

  def test_api_error
    err = AgentGIF::ApiError.new("Not found", 404)
    assert_equal 404, err.status
    assert_equal "API error 404: Not found", err.message
  end

  def test_config_default
    cfg = AgentGIF::Config.load_config
    assert_kind_of Hash, cfg
  end
end

require "tmpdir"
