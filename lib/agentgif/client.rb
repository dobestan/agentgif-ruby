# frozen_string_literal: true

# HTTP client for the AgentGIF API.

require "json"
require "net/http"
require "uri"

module AgentGIF
  class ApiError < StandardError
    attr_reader :status

    def initialize(message, status)
      @status = status
      super("API error #{status}: #{message}")
    end
  end

  class Client
    BASE_URL = "https://agentgif.com"

    def initialize(base_url: nil, api_key: nil)
      @base_url = base_url || BASE_URL
      @api_key = api_key || Config.get_api_key
    end

    # --- Auth ---

    def whoami
      get("/users/me/")
    end

    def device_auth
      post("/auth/device/", {})
    end

    def device_token(device_code)
      uri = URI("#{@base_url}/api/v1/auth/device/token/")
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "application/json"
      req.body = JSON.generate({ device_code: device_code })
      resp = execute_raw(uri, req)
      body = parse_body(resp.body)
      [body, resp.code.to_i]
    end

    # --- GIFs ---

    def search(query)
      get("/search/?q=#{encode(query)}")
    end

    def list_gifs(repo: nil)
      path = repo && !repo.empty? ? "/gifs/me/?repo=#{encode(repo)}" : "/gifs/me/"
      get(path)
    end

    def get_gif(gif_id)
      get("/gifs/#{gif_id}/")
    end

    def embed_codes(gif_id)
      data = get_gif(gif_id)
      data["embed"] || {}
    end

    def update_gif(gif_id, fields)
      patch("/gifs/#{gif_id}/", fields)
    end

    def delete_gif(gif_id)
      response = request(:delete, "/gifs/#{gif_id}/")
      return if response.code.to_i < 400

      raise ApiError.new(response.body, response.code.to_i)
    end

    def upload(gif_path, opts = {})
      boundary = "AgentGIF#{rand(10**16)}"
      body = build_multipart(gif_path, opts, boundary)

      uri = URI("#{@base_url}/api/v1/gifs/")
      req = Net::HTTP::Post.new(uri)
      req["Content-Type"] = "multipart/form-data; boundary=#{boundary}"
      req["Authorization"] = "Token #{@api_key}" unless @api_key.empty?
      req.body = body

      resp = execute_raw(uri, req)
      handle_response(resp)
    end

    # --- Badges ---

    def badge_url(provider, package, opts = {})
      params = ["provider=#{encode(provider)}", "package=#{encode(package)}"]
      opts.each { |k, v| params << "#{encode(k.to_s)}=#{encode(v)}" unless v.to_s.empty? }
      get("/badge-url/?#{params.join('&')}")
    end

    def badge_themes
      get("/themes/badges/")
    end

    # --- Generate ---

    def generate_tape(source_url: "", source_type: "", max_gifs: 5, raw_markdown: "")
      payload = { "max_gifs" => max_gifs }
      payload["source_url"] = source_url unless source_url.empty?
      payload["source_type"] = source_type unless source_type.empty?
      if !raw_markdown.empty?
        payload["source_type"] = "raw"
        payload["raw_markdown"] = raw_markdown
      end
      post("/gifs/generate/", payload)
    end

    def generate_status(job_id)
      get("/gifs/generate/#{job_id}/")
    end

    # --- Version ---

    def cli_version
      get("/cli/version/")
    end

    private

    def get(path)
      resp = request(:get, path)
      handle_response(resp)
    end

    def post(path, body)
      resp = request(:post, path, JSON.generate(body))
      handle_response(resp)
    end

    def patch(path, body)
      resp = request(:patch, path, JSON.generate(body))
      handle_response(resp)
    end

    def request(method, path, body = nil)
      uri = URI("#{@base_url}/api/v1#{path}")
      klass = {
        get: Net::HTTP::Get,
        post: Net::HTTP::Post,
        patch: Net::HTTP::Patch,
        delete: Net::HTTP::Delete
      }.fetch(method)

      req = klass.new(uri)
      req["Content-Type"] = "application/json"
      req["Authorization"] = "Token #{@api_key}" unless @api_key.empty?
      req.body = body if body

      execute_raw(uri, req)
    end

    def execute_raw(uri, req)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 30
      http.read_timeout = 60
      http.request(req)
    end

    def handle_response(resp)
      status = resp.code.to_i
      body = resp.body || ""
      if status >= 400
        msg = begin
          obj = JSON.parse(body)
          obj["error"] || obj["detail"] || body
        rescue JSON::ParserError
          body
        end
        raise ApiError.new(msg, status)
      end
      parse_body(body)
    end

    def parse_body(body)
      return nil if body.nil? || body.empty?

      JSON.parse(body)
    rescue JSON::ParserError
      nil
    end

    def encode(s)
      URI.encode_www_form_component(s.to_s)
    end

    def build_multipart(gif_path, opts, boundary)
      parts = []

      # GIF file part
      file_data = File.binread(gif_path)
      file_name = File.basename(gif_path)
      parts << "--#{boundary}\r\n" \
               "Content-Disposition: form-data; name=\"gif\"; filename=\"#{file_name}\"\r\n" \
               "Content-Type: image/gif\r\n\r\n" \
               "#{file_data}\r\n"

      # Text fields
      opts.each do |key, value|
        next if value.to_s.empty?
        next if key.to_s == "cast_path"

        parts << "--#{boundary}\r\n" \
                 "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n" \
                 "#{value}\r\n"
      end

      # Cast file (optional)
      cast_path = opts["cast_path"] || opts[:cast_path]
      if cast_path && !cast_path.empty? && File.exist?(cast_path)
        cast_data = File.binread(cast_path)
        cast_name = File.basename(cast_path)
        parts << "--#{boundary}\r\n" \
                 "Content-Disposition: form-data; name=\"cast\"; filename=\"#{cast_name}\"\r\n" \
                 "Content-Type: application/octet-stream\r\n\r\n" \
                 "#{cast_data}\r\n"
      end

      parts << "--#{boundary}--\r\n"
      parts.join
    end
  end
end
