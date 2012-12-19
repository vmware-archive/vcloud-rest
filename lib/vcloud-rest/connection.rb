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

module VCloudClient
  class UnauthorizedAccess < StandardError; end
  class WrongAPIVersion < StandardError; end
  class WrongItemIDError < StandardError; end
  class InvalidStateError < StandardError; end
  class UnhandledError < StandardError; end

  # Main class to access vCloud rest APIs
  class Connection
    attr_reader :api_url, :auth_key

    def initialize(host, username, password, org_name, api_version)
      @host = host
      @api_url = "#{host}/api"
      @username = username
      @password = password
      @org_name = org_name
      @api_version = (api_version || "5.1")
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
    end

    ##
    # List existing organizations and their IDs
    def list_organizations
      params = {
        'method' => :get,
        'command' => '/org'
      }

      response, headers = send_request(params)
      orgs = response.css('OrgList Org')

      results = {}
      orgs.each do |org|
        results[org['name']] = org['href'].gsub("#{@api_url}/org/", "")
      end
      results
    end

    ##
    # Show details about an organization:
    # - catalogs
    # - vdcs
    # - networks
    def show_organization(orgId)
      params = {
        'method' => :get,
        'command' => "/org/#{orgId}"
      }

      response, headers = send_request(params)
      catalogs = {}
      response.css("Link[type='application/vnd.vmware.vcloud.catalog+xml']").each do |item|
        catalogs[item['name']] = item['href'].gsub("#{@api_url}/catalog/", "")
      end

      vdcs = {}
      response.css("Link[type='application/vnd.vmware.vcloud.vdc+xml']").each do |item|
        vdcs[item['name']] = item['href'].gsub("#{@api_url}/vdc/", "")
      end

      networks = {}
      response.css("Link[type='application/vnd.vmware.vcloud.orgNetwork+xml']").each do |item|
        networks[item['name']] = item['href'].gsub("#{@api_url}/network/", "")
      end

      [catalogs, vdcs, networks]
    end

    ##
    # Show details about a given catalog
    def show_catalog(catalogId)
      params = {
        'method' => :get,
        'command' => "/catalog/#{catalogId}"
      }

      response, headers = send_request(params)
      description = response.css("Description").first
      description = description.text unless description.nil?

      items = {}
      response.css("CatalogItem[type='application/vnd.vmware.vcloud.catalogItem+xml']").each do |item|
        items[item['name']] = item['href'].gsub("#{@api_url}/catalogItem/", "")
      end

      [description, items]
    end

    ##
    # Show details about a given vdc:
    # - description
    # - vapps
    # - networks
    def show_vdc(vdcId)
      params = {
        'method' => :get,
        'command' => "/vdc/#{vdcId}"
      }

      response, headers = send_request(params)
      description = response.css("Description").first
      description = description.text unless description.nil?

      vapps = {}
      response.css("ResourceEntity[type='application/vnd.vmware.vcloud.vApp+xml']").each do |item|
        vapps[item['name']] = item['href'].gsub("#{@api_url}/vApp/vapp-", "")
      end

      networks = {}
      response.css("Network[type='application/vnd.vmware.vcloud.network+xml']").each do |item|
        networks[item['name']] = item['href'].gsub("#{@api_url}/network/", "")
      end

      [description, vapps, networks]
    end

    ##
    # Show details about a given catalog item:
    # - description
    # - vApp templates
    def show_catalog_item(catalogItemId)
      params = {
        'method' => :get,
        'command' => "/catalogItem/#{catalogItemId}"
      }

      response, headers = send_request(params)
      description = response.css("Description").first
      description = description.text unless description.nil?

      items = {}
      response.css("Entity[type='application/vnd.vmware.vcloud.vAppTemplate+xml']").each do |item|
        items[item['name']] = item['href'].gsub("#{@api_url}/vAppTemplate/", "")
      end

      [description, items]
    end

    ##
    # Show details about a given vapp:
    # - name
    # - description
    # - status
    # - IP
    # - Children VMs:
    #   -- IP addresses
    #   -- status
    #   -- ID
    def show_vapp(vAppId)
      params = {
        'method' => :get,
        'command' => "/vApp/vapp-#{vAppId}"
      }

      response, headers = send_request(params)

      vapp_node = response.css('VApp').first
      if vapp_node
        name = vapp_node['name']
        status = convert_status(vapp_node['status'])
      end

      description = response.css("Description").first
      description = description.text unless description.nil?

      ip = response.css('IpAddress').first
      ip = ip.text unless ip.nil?

      vms = response.css('Children Vm')
      vms_hash = {}
      vms.each do |vm|
        addresses = vm.css('rasd|Connection').collect{|n| n['ipAddress']}
        vms_hash[vm['name']] = {:addresses => addresses,
          :status => convert_status(vm['status']),
          :id => vm['href'].gsub("#{@api_url}/vApp/vm-", '')
        }
      end

      # TODO: EXPAND INFO FROM RESPONSE
      [name, description, status, ip, vms_hash]
    end

    ##
    # Delete a given vapp
    # NOTE: It doesn't verify that the vapp is shutdown
    def delete_vapp(vAppId)
      params = {
        'method' => :delete,
        'command' => "/vApp/vapp-#{vAppId}"
      }

      response, headers = send_request(params)
      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

    ##
    # Shutdown a given vapp
    def poweroff_vapp(vAppId)
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.UndeployVAppParams(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5") {
        xml.UndeployPowerAction 'powerOff'
      }
      end

      params = {
        'method' => :post,
        'command' => "/vApp/vapp-#{vAppId}/action/undeploy"
      }

      response, headers = send_request(params, builder.to_xml,
                      "application/vnd.vmware.vcloud.undeployVAppParams+xml")

      response
    end

    ##
    # Boot a given vapp
    def poweron_vapp(vAppId)
      params = {
        'method' => :post,
        'command' => "/vApp/vapp-#{vAppId}/power/action/powerOn"
      }

      response, headers = send_request(params)
      # TODO: track Task using headers[:location]
      [response, headers]
    end

    ##
    # Create a vapp starting from a template
    #
    # Params:
    # - vdc: the associated VDC
    # - vapp_name: name of the target vapp
    # - vapp_description: description of the target vapp
    # - vapp_templateid: ID of the vapp template
    def create_vapp_from_template(vdc, vapp_name, vapp_description, vapp_templateid)
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.InstantiateVAppTemplateParams(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5",
        "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
        "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1",
        "name" => vapp_name,
        "deploy" => "true",
        "powerOn" => "true") {
        xml.Description vapp_description
        xml.Source("href" => "#{@api_url}/vAppTemplate/#{vapp_templateid}")
      }
      end

      params = {
        "method" => :post,
        "command" => "/vdc/#{vdc}/action/instantiateVAppTemplate"
      }

      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.instantiateVAppTemplateParams+xml")

      vapp_id = headers[:location].gsub("#{@api_url}/vApp/vapp-", "")

      task = response.css("VApp Task[operationName='vdcInstantiateVapp']").first
      task_id = task["href"].gsub("#{@api_url}/task/", "")

      [vapp_id, task_id]
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
            puts "Warning: unattended code #{response.code}"
          end

          # TODO: handle asynch properly, see TasksList
          [Nokogiri.parse(response), response.headers]
        rescue RestClient::Unauthorized => e
          raise UnauthorizedAccess, "Client not authorized. Please check your credentials."
        rescue RestClient::BadRequest => e
          body = Nokogiri.parse(e.http_body)
          message = body.css("Error").first["message"]

          case message
          when /The request has invalid accept header/
            raise WrongAPIVersion, "Invalid accept header. Please verify that the server supports v.#{@api_version} or specify a different API Version."
          when /validation error on field 'id': String value has invalid format or length/
            raise WrongItemIDError, "Invalid ID specified. Please verify that the item exists and correctly typed."
          when /The requested operation could not be executed on vApp "(.*)". Stop the vApp and try again/
            raise InvalidStateError, "Invalid request. Stop vApp '#{$1}' and try again."
          else
            raise UnhandledError, "BadRequest - unhandled error: #{message}.\nPlease report this issue."
          end
        end
      end

      ##
      # Convert status codes into human readable description
      def convert_status(status_code)
        case status_code.to_i
          when 3
            'suspended'
          when 4
            'running'
          when 8
            'stopped'
          else
            "Unknown #{status_code}"
        end
      end
  end # class
end
