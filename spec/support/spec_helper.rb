## Support for 1.8.x
unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end
##

require 'simplecov'
SimpleCov.start

require 'coveralls'
Coveralls.wear!

require 'webmock/rspec'
require 'vcr'
require 'uri'
require_relative '../../lib/vcloud-rest/connection'

def extract_host(full_host)
  URI.parse(full_host).host
end

def default_credentials
  {:host => 'https://testurl.local',
   :username => 'testuser',
   :password => 'testpass',
   :org => 'testorg',
   :api_version => '5.1'
  }
end

RSpec.configure do |config|
  config.raise_errors_for_deprecations!
end

def credentials
  @credentials ||= begin
    data = default_credentials
    data.merge!(YAML.load_file("test_credentials.yml")) if File.exists?("test_credentials.yml")
    data
  end
end

VCR.configure do |c|
  creds = credentials
  vcloud_host = creds[:host]
  vcloud_user = creds[:username]
  vcloud_passwd = creds[:password]
  vcloud_org = creds[:org]

  user = URI.encode_www_form_component "#{vcloud_user}@#{vcloud_org}"
  passwd = URI.encode_www_form_component "#{vcloud_passwd}"
  credential_string = "#{user}:#{passwd}"

  c.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  c.hook_into :webmock
  c.ignore_localhost = true
  c.filter_sensitive_data("testpass") { vcloud_passwd }
  c.filter_sensitive_data("testpass") { passwd }
  c.filter_sensitive_data("testuser") { vcloud_user }
  c.filter_sensitive_data("testorg") { vcloud_org }
  c.filter_sensitive_data("testuser%40testorg:testpass") { credential_string }
  c.filter_sensitive_data("testurl.local") { extract_host(vcloud_host) } if vcloud_host

  # Register custom matcher to check important headers remain valid
  c.register_request_matcher :auth_header do |new_request, old_request|
    headers_new, headers_old = new_request.headers, old_request.headers

    %w{ X-Vcloud-Authorization Accept Content-Type }.all? do |header|
      !headers_old.has_key?(header) ||
          (headers_new[header] == headers_old[header])
    end
  end

  c.register_request_matcher :payload do |new_request, old_request|
    body_new, body_old = new_request.body, old_request.body

    body_old == body_new
  end

  c.default_cassette_options = { :decode_compressed_response => true,
                       :match_requests_on => [:method, :host, :path, :auth_header, :payload] }

  # Decomment this line to enable VCR debug logging
  # Helpful to identify why a vcr log failed to match the generated query.
  #c.debug_logger = File.open("vcr.log", 'w')
end
