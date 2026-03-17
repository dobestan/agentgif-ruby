# frozen_string_literal: true

# AgentGIF CLI (Ruby) — GIF for humans. Cast for agents.
#
# Install: gem install agentgif
# Usage:   agentgif login | upload | search | badge
#
# Full documentation: https://agentgif.com/docs/cli/

require_relative "config"
require_relative "client"

module AgentGIF
  VERSION = "0.2.0"

  module CLI
    HELP = <<~TEXT
      AgentGIF — GIF for humans. Cast for agents.

      Usage: agentgif <command> [options]

      Commands:
        login                Open browser to authenticate
        logout               Remove stored credentials
        whoami               Show current user info

        upload <gif>         Upload a GIF
        search <query>       Search public GIFs
        list                 List your GIFs
        info <gifId>         Show GIF details (JSON)
        embed <gifId>        Show embed codes
        update <gifId>       Update GIF metadata
        delete <gifId>       Delete a GIF

        generate <url>       Generate GIFs from a README or package docs
        generate-status <id> Check status of a generate job
        record <tape>        Record a VHS tape and upload the GIF

        badge url            Generate badge URL + embed codes
        badge themes         List available terminal themes

        version              Show version

      Docs: https://agentgif.com/docs/cli/
    TEXT

    module_function

    def run(args)
      command = args.shift
      case command
      when "login"          then cmd_login
      when "logout"         then cmd_logout
      when "whoami"         then cmd_whoami
      when "upload"         then cmd_upload(args)
      when "search"         then cmd_search(args)
      when "list"           then cmd_list(args)
      when "info"           then cmd_info(args)
      when "embed"          then cmd_embed(args)
      when "update"         then cmd_update(args)
      when "delete"         then cmd_delete(args)
      when "generate"       then cmd_generate(args)
      when "generate-status" then cmd_generate_status(args)
      when "record"         then cmd_record(args)
      when "badge"          then cmd_badge(args)
      when "version", "--version", "-v"
        puts "agentgif #{VERSION}"
      when "help", "--help", "-h", nil
        puts HELP
      else
        warn "Unknown command: #{command}"
        warn "Run 'agentgif help' for usage."
        exit 1
      end
    rescue AgentGIF::ApiError => e
      warn "Error: #{e.message}"
      exit 1
    rescue Errno::ECONNREFUSED, SocketError => e
      warn "Connection error: #{e.message}"
      exit 1
    end

    # --- Authentication ---

    def cmd_login
      client = Client.new
      data = client.device_auth
      code = data["user_code"]
      url = data["verification_url"]
      device_code = data["device_code"]
      interval = (data["interval"] || 5).to_i

      puts "  Code: #{code}"
      puts "  Open: #{url}"
      puts ""

      open_browser(url)

      puts "Waiting for authentication..."
      loop do
        sleep(interval)
        body, status = client.device_token(device_code)
        if status == 200 && body && body["api_key"]
          Config.save_credentials(body["api_key"], body["username"] || "")
          puts "Logged in as #{body['username']}"
          return
        elsif status == 400
          detail = body && body["detail"]
          if detail == "authorization_pending"
            next
          else
            warn "Auth failed: #{detail || 'unknown error'}"
            exit 1
          end
        else
          warn "Unexpected response (#{status})"
          exit 1
        end
      end
    end

    def cmd_logout
      Config.clear_credentials
      puts "Logged out."
    end

    def cmd_whoami
      require_auth
      data = client.whoami
      puts "  Username: #{data['username']}"
      puts "  Email:    #{data['email']}" if data["email"]
    end

    # --- GIF Management ---

    def cmd_upload(args)
      require_auth
      opts = parse_opts(args, %w[-t --title -d --description -c --command --tags --cast --theme], %w[--unlisted --no-repo])
      gif_path = opts[:positional].first
      abort "Usage: agentgif upload <gif> [options]" unless gif_path
      abort "File not found: #{gif_path}" unless File.exist?(gif_path)

      fields = {}
      fields["title"] = opts["-t"] || opts["--title"] if opts["-t"] || opts["--title"]
      fields["description"] = opts["-d"] || opts["--description"] if opts["-d"] || opts["--description"]
      fields["command"] = opts["-c"] || opts["--command"] if opts["-c"] || opts["--command"]
      fields["tags"] = opts["--tags"] if opts["--tags"]
      fields["cast_path"] = opts["--cast"] if opts["--cast"]
      fields["theme"] = opts["--theme"] if opts["--theme"]
      fields["unlisted"] = "true" if opts["--unlisted"]

      unless opts["--no-repo"]
        repo = detect_repo
        fields["repo"] = repo if repo
      end

      data = client.upload(gif_path, fields)
      gif_id = data["id"]
      puts "Uploaded: #{Client::BASE_URL}/g/#{gif_id}"
    end

    def cmd_search(args)
      query = args.join(" ")
      abort "Usage: agentgif search <query>" if query.empty?
      data = Client.new.search(query)
      results = data["results"] || []
      if results.empty?
        puts "No results."
        return
      end
      results.each do |gif|
        cmd = gif["command"] ? "  (#{gif['command']})" : ""
        puts "  #{gif['id']}  #{gif['title']}#{cmd}"
      end
    end

    def cmd_list(args)
      require_auth
      opts = parse_opts(args, %w[--repo], [])
      repo = opts["--repo"] || ""
      data = client.list_gifs(repo: repo)
      gifs = data.is_a?(Array) ? data : (data["results"] || [])
      if gifs.empty?
        puts "No GIFs found."
        return
      end
      gifs.each do |gif|
        puts "  #{gif['id']}  #{gif['title']}"
      end
    end

    def cmd_info(args)
      gif_id = args.first
      abort "Usage: agentgif info <gifId>" unless gif_id
      data = client.get_gif(gif_id)
      puts JSON.pretty_generate(data)
    end

    def cmd_embed(args)
      opts = parse_opts(args, %w[-f --format], [])
      gif_id = opts[:positional].first
      abort "Usage: agentgif embed <gifId> [-f format]" unless gif_id
      fmt = opts["-f"] || opts["--format"] || "all"

      data = client.embed_codes(gif_id)
      if fmt == "all"
        data.each do |key, code|
          puts "--- #{key} ---"
          puts code
          puts ""
        end
      else
        code = data[fmt]
        if code
          puts code
        else
          warn "Unknown format: #{fmt}. Available: #{data.keys.join(', ')}"
          exit 1
        end
      end
    end

    def cmd_update(args)
      require_auth
      opts = parse_opts(args, %w[-t --title -d --description -c --command --tags], [])
      gif_id = opts[:positional].first
      abort "Usage: agentgif update <gifId> [options]" unless gif_id

      fields = {}
      fields["title"] = opts["-t"] || opts["--title"] if opts["-t"] || opts["--title"]
      fields["description"] = opts["-d"] || opts["--description"] if opts["-d"] || opts["--description"]
      fields["command"] = opts["-c"] || opts["--command"] if opts["-c"] || opts["--command"]
      fields["tags"] = opts["--tags"] if opts["--tags"]

      if fields.empty?
        warn "No fields to update. Use -t, -d, -c, or --tags."
        exit 1
      end

      data = client.update_gif(gif_id, fields)
      puts "Updated: #{data['id']}"
    end

    def cmd_delete(args)
      opts = parse_opts(args, [], %w[-y --yes])
      gif_id = opts[:positional].first
      abort "Usage: agentgif delete <gifId> [-y]" unless gif_id
      require_auth

      unless opts["-y"] || opts["--yes"]
        print "Delete #{gif_id}? [y/N] "
        answer = $stdin.gets&.strip
        unless answer&.downcase == "y"
          puts "Cancelled."
          return
        end
      end

      client.delete_gif(gif_id)
      puts "Deleted: #{gif_id}"
    end

    # --- Generate ---

    def cmd_generate(args)
      require_auth
      opts = parse_opts(args, %w[--max --max-gifs --source-type --pypi --npm], %w[--no-wait])

      source_url = opts[:positional].first || ""
      source_type = opts["--source-type"] || ""
      max_gifs = (opts["--max"] || opts["--max-gifs"] || "5").to_i

      if opts["--pypi"]
        pkg = opts["--pypi"]
        source_url = "https://pypi.org/project/#{pkg}/"
        source_type = "pypi"
      elsif opts["--npm"]
        pkg = opts["--npm"]
        source_url = "https://www.npmjs.com/package/#{pkg}"
        source_type = "npm"
      elsif !source_url.empty? && source_type.empty?
        source_type = detect_source_type(source_url)
      end

      abort "Usage: agentgif generate <url> [--pypi PKG] [--npm PKG] [--max N] [--no-wait]" if source_url.empty?

      job = client.generate_tape(source_url: source_url, source_type: source_type, max_gifs: max_gifs)
      job_id = job["job_id"]

      if opts["--no-wait"]
        puts "Job created: #{job_id}"
        puts "  Check: agentgif generate-status #{job_id}"
        return
      end

      puts "Generating GIFs..."
      poll_generate_job(job_id)
    end

    def cmd_generate_status(args)
      require_auth
      opts = parse_opts(args, [], %w[--poll])
      job_id = opts[:positional].first
      abort "Usage: agentgif generate-status <job_id> [--poll]" unless job_id

      if opts["--poll"]
        poll_generate_job(job_id)
      else
        data = client.generate_status(job_id)
        puts "  Status:         #{data['status']}"
        puts "  Commands found: #{data['commands_found']}" if data["commands_found"]
        puts "  GIFs created:   #{data['gifs_created']}" if data["gifs_created"]
        puts "  Error:          #{data['error_message']}" if data["error_message"]
        gifs = data["gifs"] || []
        unless gifs.empty?
          puts "  GIFs:"
          gifs.each do |gif|
            puts "    #{gif['id']}  #{gif['title']}  #{gif['url']}"
          end
        end
      end
    end

    def cmd_record(args)
      require_auth
      opts = parse_opts(args, %w[-t --title -d --description -c --command --tags --theme], %w[--unlisted --no-repo])
      tape_file = opts[:positional].first
      abort "Usage: agentgif record <tape_file> [upload options...]" unless tape_file
      abort "File not found: #{tape_file}" unless File.exist?(tape_file)

      unless system("which", "vhs", out: File::NULL, err: File::NULL)
        abort "Error: VHS not found. Install from https://github.com/charmbracelet/vhs"
      end

      puts "Running VHS: #{tape_file}"
      unless system("vhs", tape_file)
        abort "VHS recording failed."
      end

      # Parse tape file for Output line to find GIF path
      gif_path = nil
      File.readlines(tape_file).each do |line|
        if line.strip.match(/\AOutput\s+(.+)/i)
          gif_path = $1.strip.gsub(/["']/, "")
          break
        end
      end

      gif_path ||= tape_file.sub(/\.[^.]+\z/, ".gif")
      abort "GIF not found: #{gif_path}" unless File.exist?(gif_path)

      puts "Uploading: #{gif_path}"
      # Reuse upload logic by building args and calling cmd_upload
      upload_args = [gif_path]
      upload_args.push("-t", opts["-t"] || opts["--title"]) if opts["-t"] || opts["--title"]
      upload_args.push("-d", opts["-d"] || opts["--description"]) if opts["-d"] || opts["--description"]
      upload_args.push("-c", opts["-c"] || opts["--command"]) if opts["-c"] || opts["--command"]
      upload_args.push("--tags", opts["--tags"]) if opts["--tags"]
      upload_args.push("--theme", opts["--theme"]) if opts["--theme"]
      upload_args.push("--unlisted") if opts["--unlisted"]
      upload_args.push("--no-repo") if opts["--no-repo"]
      cmd_upload(upload_args)
    end

    # --- Badge ---

    def cmd_badge(args)
      subcmd = args.shift
      case subcmd
      when "url"    then cmd_badge_url(args)
      when "themes" then cmd_badge_themes
      else
        puts "Usage: agentgif badge <url|themes>"
      end
    end

    def cmd_badge_url(args)
      opts = parse_opts(args, %w[-p --provider -k --package -m --metric --theme --style -f --format], [])
      provider = opts["-p"] || opts["--provider"]
      package = opts["-k"] || opts["--package"]
      abort "Usage: agentgif badge url -p <provider> -k <package>" unless provider && package

      extra = {}
      extra["metric"] = opts["-m"] || opts["--metric"] if opts["-m"] || opts["--metric"]
      extra["theme"] = opts["--theme"] if opts["--theme"]
      extra["style"] = opts["--style"] if opts["--style"]
      fmt = opts["-f"] || opts["--format"] || "all"

      data = Client.new.badge_url(provider, package, extra)
      if fmt == "all"
        data.each do |key, val|
          puts "#{key}: #{val}"
        end
      else
        val = data[fmt] || data["url"]
        puts val if val
      end
    end

    def cmd_badge_themes
      data = Client.new.badge_themes
      themes = data.is_a?(Array) ? data : (data["themes"] || [])
      themes.each { |t| puts "  #{t}" }
    end

    # --- Helpers ---

    def require_auth
      key = Config.get_api_key
      if key.empty?
        warn "Not logged in. Run: agentgif login"
        exit 1
      end
    end

    def client
      @client ||= Client.new
    end

    def detect_source_type(url)
      case url
      when /github\.com/  then "github"
      when /pypi\.org/    then "pypi"
      when /npmjs\.com/   then "npm"
      else ""
      end
    end

    def poll_generate_job(job_id)
      start = Time.now
      prev_status = ""
      loop do
        if Time.now - start > 300
          warn "Timed out after 5 minutes. Check status:"
          warn "  agentgif generate-status #{job_id}"
          exit 1
        end

        sleep(2)

        begin
          data = client.generate_status(job_id)
        rescue AgentGIF::ApiError => e
          next if e.status >= 500
          raise
        end

        current = data["status"] || ""
        if current != prev_status
          puts "  Status: #{current}"
          prev_status = current
        end

        case current
        when "completed"
          gifs = data["gifs"] || []
          count = data["gifs_created"] || gifs.length
          puts "Done! #{count} GIFs generated."
          gifs.each do |gif|
            puts "  #{gif['id']}  #{gif['title']}  #{gif['url']}"
          end
          return
        when "failed"
          warn "Generation failed: #{data['error_message'] || 'Unknown error'}"
          exit 1
        end
      end
    end

    def detect_repo
      remote = `git remote get-url origin 2>/dev/null`.strip
      return nil if remote.empty?

      # git@github.com:user/repo.git → user/repo
      if remote.match?(%r{git@github\.com:(.+?)(?:\.git)?$})
        remote.match(%r{git@github\.com:(.+?)(?:\.git)?$})[1]
      elsif remote.match?(%r{github\.com/(.+?)(?:\.git)?$})
        remote.match(%r{github\.com/(.+?)(?:\.git)?$})[1]
      end
    end

    def open_browser(url)
      case RUBY_PLATFORM
      when /darwin/  then system("open", url)
      when /linux/   then system("xdg-open", url)
      when /mswin|mingw/ then system("start", url)
      end
    end

    def parse_opts(args, value_flags, bool_flags)
      result = { positional: [] }
      i = 0
      while i < args.length
        arg = args[i]
        if value_flags.include?(arg)
          i += 1
          result[arg] = args[i]
        elsif bool_flags.include?(arg)
          result[arg] = true
        else
          result[:positional] << arg
        end
        i += 1
      end
      result
    end

    def check_for_updates
      data = Client.new.cli_version
      latest = data["latest"]
      return unless latest

      current_parts = VERSION.split(".").map(&:to_i)
      latest_parts = latest.split(".").map(&:to_i)
      return unless (latest_parts <=> current_parts) == 1

      warn "Update available: #{VERSION} → #{latest}  (gem install agentgif)"
    rescue StandardError
      # Silently ignore update check failures
    end
  end
end
