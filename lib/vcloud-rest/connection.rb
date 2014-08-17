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
require 'uri'

require 'vcloud-rest/vcloud/vapp'
require 'vcloud-rest/vcloud/org'
require 'vcloud-rest/vcloud/catalog'
require 'vcloud-rest/vcloud/vdc'
require 'vcloud-rest/vcloud/vm'
require 'vcloud-rest/vcloud/ovf'
require 'vcloud-rest/vcloud/media'
require 'vcloud-rest/vcloud/network'
require 'vcloud-rest/vcloud/disk'
require 'vcloud-rest/vcloud/extensibility'

module VCloudClient
  class UnauthorizedAccess < StandardError; end
  class WrongAPIVersion < StandardError; end
  class WrongItemIDError < StandardError; end
  class InvalidStateError < StandardError; end
  class InternalServerError < StandardError; end
  class OVFError < StandardError; end
  class MethodNotAllowed < StandardError; end
  class UnhandledError < StandardError; end

  # Main class to access vCloud rest APIs
  class Connection
    attr_reader :api_url, :auth_key
    attr_reader :extensibility

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

      extensibility_link = response.css("Link[rel='down:extensibility']")
      @extensibility = extensibility_link.first['href'] unless extensibility_link.empty?

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
    ensure
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
        invocation_params = {:method => params['method'],
                             :headers => headers,
                             :url => "#{@api_url}#{params['command']}",
                             :payload => payload}

        if @auth_key
          headers.merge!({:x_vcloud_authorization => @auth_key})
        else
          invocation_params.merge!({:user => "#{@username}@#{@org_name}",
                                    :password => @password })
        end

        headers.merge!({:content_type => content_type}) if content_type

        request = RestClient::Request.new(invocation_params)

        begin
          response = request.execute
          if ![200, 201, 202, 204].include?(response.code)
            @logger.warn "Warning: unattended code #{response.code}"
          end

          # TODO eliminate double parse of response.
          @logger.debug "Send request result: #{Nokogiri.parse(response)}"

          # TODO parse using Nokogiri::XML to improve parse performnace.
          [Nokogiri.parse(response), response.headers]
        rescue RestClient::Unauthorized => e
          raise UnauthorizedAccess, "Client not authorized. Please check your credentials."
        rescue RestClient::BadRequest => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]
          humanize_badrequest(message)
          # TODO add debug response logging
        rescue RestClient::Forbidden => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]
          # TODO add debug response logging
          raise UnauthorizedAccess, "Operation not permitted: #{message}."
        rescue RestClient::InternalServerError => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]
          # TODO add debug response logging
          raise InternalServerError, "Internal Server Error: #{message}."
        rescue RestClient::MethodNotAllowed => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]
          # TODO add debug response logging
          raise MethodNotAllowed, "#{params['method']} to #{params['command']} not allowed: #{message}."
        # TODO add socket error exception handling
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
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end

    ##
    # Discard suspended state of a vApp/VM
    def discard_suspended_state_action(id, type=:vapp)
      params = {
          "method" => :post,
          "command" => "/vApp/#{type}-#{id}/action/discardSuspendedState"
      }
      response, headers = send_request(params)
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end

    ##
    # Create a new vapp/vm snapshot (overwrites any existing)
    def create_snapshot_action(id, description="New Snapshot", type=:vapp)
      params = {
          "method" => :post,
          "command" => "/vApp/#{type}-#{id}/action/createSnapshot"
      }
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.CreateSnapshotParams(
            "xmlns" => "http://www.vmware.com/vcloud/v1.5") {
          xml.Description description
        }
      end
      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.createSnapshotParams+xml")
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end

    ##
    # Revert to an existing snapshot (vapp/vm)
    def revert_snapshot_action(id, type=:vapp)
      params = {
          "method" => :post,
          "command" => "/vApp/#{type}-#{id}/action/revertToCurrentSnapshot"
      }
      response, headers = send_request(params)
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end

    ##
    # Discard all existing snapshots (vapp/vm)
    def discard_snapshot_action(id, type=:vapp)
      params = {
          "method" => :post,
          "command" => "/vApp/#{type}-#{id}/action/removeAllSnapshots"
      }
      response, headers = send_request(params)
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end

    ##
    # Upload a large file in configurable chunks, output an optional progressbar
    def upload_file(uploadURL, uploadFile, progressUrl, config={})
      raise ::IOError, "#{uploadFile} not found." unless File.exists?(uploadFile)

      # Set chunksize to 10M if not specified otherwise
      chunkSize = (config[:chunksize] || 10485760)

      # Set progress bar to default format if not specified otherwise
      progressBarFormat = (config[:progressbar_format] || "%e <%B> %p%% %t")

      # Set progress bar length to 120 if not specified otherwise
      progressBarLength = (config[:progressbar_length] || 120)

      # Open our file for upload
      uploadFileHandle = File.new(uploadFile, "rb" )
      fileName = File.basename(uploadFileHandle)

      progressBarTitle = "Uploading: " + uploadFile.to_s

      # Create a progressbar object if progress bar is enabled
      if config[:progressbar_enable] == true && uploadFileHandle.size.to_i > chunkSize
        progressbar = ProgressBar.create(
          :title => progressBarTitle,
          :starting_at => 0,
          :total => uploadFileHandle.size.to_i,
          :length => progressBarLength,
          :format => progressBarFormat
        )
      else
        @logger.info progressBarTitle
      end
      # Create a new HTTP client
      clnt = HTTPClient.new

      # Disable SSL cert verification
      clnt.ssl_config.verify_mode=(OpenSSL::SSL::VERIFY_NONE)

      # Suppress SSL depth message
      clnt.ssl_config.verify_callback=proc{ |ok, ctx|; true };

      # Perform ranged upload until the file reaches its end
      until uploadFileHandle.eof?

        # Create ranges for this chunk upload
        rangeStart = uploadFileHandle.pos
        rangeStop = uploadFileHandle.pos.to_i + chunkSize

        # Read current chunk
        fileContent = uploadFileHandle.read(chunkSize)

        # If statement to handle last chunk transfer if is > than filesize
        if rangeStop.to_i > uploadFileHandle.size.to_i
          contentRange = "bytes #{rangeStart.to_s}-#{uploadFileHandle.size.to_s}/#{uploadFileHandle.size.to_s}"
          rangeLen = uploadFileHandle.size.to_i - rangeStart.to_i
        else
          contentRange = "bytes #{rangeStart.to_s}-#{rangeStop.to_s}/#{uploadFileHandle.size.to_s}"
          rangeLen = rangeStop.to_i - rangeStart.to_i
        end

        # Build headers
        extheader = {
          'x-vcloud-authorization' => @auth_key,
          'Content-Range' => contentRange,
          'Content-Length' => rangeLen.to_s
        }

        begin
          uploadRequest = "#{@host_url}#{uploadURL}"
          connection = clnt.request('PUT', uploadRequest, nil, fileContent, extheader)

          if config[:progressbar_enable] == true && uploadFileHandle.size.to_i > chunkSize
            params = {
              'method' => :get,
              'command' => progressUrl
            }
            response, headers = send_request(params)

            response.css("Files File [name='#{fileName}']").each do |file|
              progressbar.progress=file[:bytesTransferred].to_i
            end
          end
        rescue
          retryTime = (config[:retry_time] || 5)
          @logger.warn "Range #{contentRange} failed to upload, retrying the chunk in #{retryTime.to_s} seconds, to stop the action press CTRL+C."
          sleep retryTime.to_i
          retry
        end
      end
      uploadFileHandle.close
    end

  end # class
end
