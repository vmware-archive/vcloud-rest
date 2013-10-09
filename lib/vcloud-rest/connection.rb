#
# Author:: Stefano Tortarolo (<stefano.tortarolo@gmail.com>)
# Copyright:: Copyright (c) 2012
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'rest-client'
require 'nokogiri'
require 'httpclient'
require 'ruby-progressbar'
require 'logger'

require 'vcloud-rest/vcloud/vapp'
require 'vcloud-rest/vcloud/org'
require 'vcloud-rest/vcloud/catalog'
require 'vcloud-rest/vcloud/vdc'
require 'vcloud-rest/vcloud/vm'
require 'vcloud-rest/vcloud/ovf'

module VCloudClient
  class UnauthorizedAccess < StandardError; end
  class WrongAPIVersion < StandardError; end
  class WrongItemIDError < StandardError; end
  class InvalidStateError < StandardError; end
  class InternalServerError < StandardError; end
  class UnhandledError < StandardError; end


  # Main class to access vCloud rest APIs
  class Connection
    attr_reader :api_url, :auth_key

    def initialize(host, username, password, org_name, api_version)
      @host = host
      @api_url = "#{host}/api"
      @host_url = "#{host}"
      @username = username
      @password = password
      @org_name = org_name
      @api_version = (api_version || "5.1")

      init_logger
    end

    ##
    # Authenticate against the specified server
    def login
      params = {
        'method' => :post,
        'command' => '/sessions'
      }

      response, headers = send_request(params)

      if !headers.has_key?(:x_vcloud_authorization)
        raise "Unable to authenticate: missing x_vcloud_authorization header"
      end

      @auth_key = headers[:x_vcloud_authorization]
    end

    ##
    # Destroy the current session
    def logout
      params = {
        'method' => :delete,
        'command' => '/session'
      }

      response, headers = send_request(params)
      # reset auth key to nil
      @auth_key = nil
    end

    ##
    # Fetch information for a given task
    def get_task(taskid)
      params = {
        'method' => :get,
        'command' => "/task/#{taskid}"
      }

      response, headers = send_request(params)

      task = response.css('Task').first
      status = task['status']
      start_time = task['startTime']
      end_time = task['endTime']

      { :status => status, :start_time => start_time, :end_time => end_time, :response => response }
    end

    ##
    # Poll a given task until completion
    def wait_task_completion(taskid)
      errormsg = nil
      task = {}

      loop do
        task = get_task(taskid)
        break if task[:status] != 'running'
        sleep 1
      end

      if task[:status] == 'error'
        errormsg = task[:response].css("Error").first
        errormsg = "Error code #{errormsg['majorErrorCode']} - #{errormsg['message']}"
      end

      { :status => task[:status], :errormsg => errormsg,
        :start_time => task[:start_time], :end_time => task[:end_time] }
    end

    private
      ##
      # Sends a synchronous request to the vCloud API and returns the response as parsed XML + headers.
      def send_request(params, payload=nil, content_type=nil)
        headers = {:accept => "application/*+xml;version=#{@api_version}"}
        if @auth_key
          headers.merge!({:x_vcloud_authorization => @auth_key})
        end

        if content_type
          headers.merge!({:content_type => content_type})
        end

        request = RestClient::Request.new(:method => params['method'],
                                         :user => "#{@username}@#{@org_name}",
                                         :password => @password,
                                         :headers => headers,
                                         :url => "#{@api_url}#{params['command']}",
                                         :payload => payload)

        begin
          response = request.execute
          if ![200, 201, 202, 204].include?(response.code)
            @logger.warn "Warning: unattended code #{response.code}"
          end

          @logger.debug "Send request result: #{Nokogiri.parse(response)}"

          [Nokogiri.parse(response), response.headers]
        rescue RestClient::Unauthorized => e
          raise UnauthorizedAccess, "Client not authorized. Please check your credentials."
        rescue RestClient::BadRequest => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]
          humanize_badrequest(message)
        rescue RestClient::Forbidden => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]
          raise UnauthorizedAccess, "Operation not permitted: #{message}."
        rescue RestClient::InternalServerError => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]
          raise InternalServerError, "Internal Server Error: #{message}."
        end
      end

      ##
      # Convert vApp status codes into human readable description
      def convert_vapp_status(status_code)
        case status_code.to_i
          when 0
            'suspended'
          when 3
            'paused'
          when 4
            'running'
          when 8
            'stopped'
          when 10
            'mixed'
          else
            "Unknown #{status_code}"
        end
      end

      def init_logger
        level = if ENV["VCLOUD_REST_DEBUG_LEVEL"]
            Logger::Severity.constants.find_index ENV["VCLOUD_REST_DEBUG_LEVEL"].upcase.to_sym
          else
            Logger::WARN
          end
        @logger = Logger.new(ENV["VCLOUD_REST_LOG_FILE"] || STDOUT)
        @logger.level = level
      end

      def humanize_badrequest(message)
        case message
        when /The request has invalid accept header/
          raise WrongAPIVersion, "Invalid accept header. Please verify that the server supports v.#{@api_version} or specify a different API Version."
        when /validation error on field 'id': String value has invalid format or length/
          raise WrongItemIDError, "Invalid ID specified. Please verify that the item exists and correctly typed."
        when /The requested operation could not be executed on vApp "(.*)". Stop the vApp and try again/
          raise InvalidStateError, "Invalid request because vApp is running. Stop vApp '#{$1}' and try again."
        when /The requested operation could not be executed since vApp "(.*)" is not running/
          raise InvalidStateError, "Invalid request because vApp is stopped. Start vApp '#{$1}' and try again."
        else
          raise UnhandledError, "BadRequest - unhandled error: #{message}.\nPlease report this issue."
        end
      end

    ##
    # Generic method to send power actions to vApp/VM
    #
    # i.e., 'suspend', 'powerOn'
    def power_action(id, action, type=:vapp)
      target = "#{type}-#{id}"

      params = {
        'method' => :post,
        'command' => "/vApp/#{target}/power/action/#{action}"
      }

      response, headers = send_request(params)
      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end
  end # class
end
