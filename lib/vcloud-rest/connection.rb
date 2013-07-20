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
  class InternalServerError < StandardError; end
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
    # Fetch existing organizations and their IDs
    def get_organizations
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
    # Fetch details about an organization:
    # - catalogs
    # - vdcs
    # - networks
    def get_organization(orgId)
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

      tasklists = {}
      response.css("Link[type='application/vnd.vmware.vcloud.tasksList+xml']").each do |item|
        tasklists[item['name']] = item['href'].gsub("#{@api_url}/tasksList/", "")
      end

      { :catalogs => catalogs, :vdcs => vdcs, :networks => networks, :tasklists => tasklists }
    end

    ##
    # Fetch details about a given catalog
    def get_catalog(catalogId)
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
      { :description => description, :items => items }
    end

    ##
    # Fetch details about a given vdc:
    # - description
    # - vapps
    # - networks
    def get_vdc(vdcId)
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
      { :description => description, :vapps => vapps, :networks => networks }
    end

    ##
    # Fetch details about a given catalog item:
    # - description
    # - vApp templates
    def get_catalog_item(catalogItemId)
      params = {
        'method' => :get,
        'command' => "/catalogItem/#{catalogItemId}"
      }

      response, headers = send_request(params)
      description = response.css("Description").first
      description = description.text unless description.nil?

      items = {}
      response.css("Entity[type='application/vnd.vmware.vcloud.vAppTemplate+xml']").each do |item|
        items[item['name']] = item['href'].gsub("#{@api_url}/vAppTemplate/vappTemplate-", "")
      end
      { :description => description, :items => items }
    end

    ##
    # Fetch details about a given vapp:
    # - name
    # - description
    # - status
    # - IP
    # - Children VMs:
    #   -- IP addresses
    #   -- status
    #   -- ID
    def get_vapp(vAppId)
      params = {
        'method' => :get,
        'command' => "/vApp/vapp-#{vAppId}"
      }

      response, headers = send_request(params)

      vapp_node = response.css('VApp').first
      if vapp_node
        name = vapp_node['name']
        status = convert_vapp_status(vapp_node['status'])
      end

      description = response.css("Description").first
      description = description.text unless description.nil?

      ip = response.css('IpAddress').first
      ip = ip.text unless ip.nil?

      vms = response.css('Children Vm')
      vms_hash = {}

      # ipAddress could be namespaced or not: see https://github.com/astratto/vcloud-rest/issues/3
      vms.each do |vm|
        vapp_local_id = vm.css('VAppScopedLocalId')
        addresses = vm.css('rasd|Connection').collect{|n| n['vcloud:ipAddress'] || n['ipAddress'] }
        vms_hash[vm['name']] = {
          :addresses => addresses,
          :status => convert_vapp_status(vm['status']),
          :id => vm['href'].gsub("#{@api_url}/vApp/vm-", ''),
          :vapp_scoped_local_id => vapp_local_id.text
        }
      end

      # TODO: EXPAND INFO FROM RESPONSE
      { :name => name, :description => description, :status => status, :ip => ip, :vms_hash => vms_hash }
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
      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

    ##
    # Boot a given vapp
    def poweron_vapp(vAppId)
      params = {
        'method' => :post,
        'command' => "/vApp/vapp-#{vAppId}/power/action/powerOn"
      }

      response, headers = send_request(params)
      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

    ##
    # Create a vapp starting from a template
    #
    # Params:
    # - vdc: the associated VDC
    # - vapp_name: name of the target vapp
    # - vapp_description: description of the target vapp
    # - vapp_templateid: ID of the vapp template
    def create_vapp_from_template(vdc, vapp_name, vapp_description, vapp_templateid, poweron=false)
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.InstantiateVAppTemplateParams(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5",
        "xmlns:xsi" => "http://www.w3.org/2001/XMLSchema-instance",
        "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1",
        "name" => vapp_name,
        "deploy" => "true",
        "powerOn" => poweron) {
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

      { :vapp_id => vapp_id, :task_id => task_id }
    end

    ##
    # Compose a vapp using existing virtual machines
    #
    # Params:
    # - vdc: the associated VDC
    # - vapp_name: name of the target vapp
    # - vapp_description: description of the target vapp
    # - vm_list: hash with IDs of the VMs to be used in the composing process
    # - network_config: hash of the network configuration for the vapp
    def compose_vapp_from_vm(vdc, vapp_name, vapp_description, vm_list={}, network_config={})
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.ComposeVAppParams(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5",
        "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1",
        "name" => vapp_name) {
        xml.Description vapp_description
        xml.InstantiationParams {
          xml.NetworkConfigSection {
            xml['ovf'].Info "Configuration parameters for logical networks"
            xml.NetworkConfig("networkName" => network_config[:name]) {
              xml.Configuration {
                xml.IpScopes {
                  xml.IpScope {
                    xml.IsInherited(network_config[:is_inherited] || "false")
                    xml.Gateway network_config[:gateway]
                    xml.Netmask network_config[:netmask]
                    xml.Dns1 network_config[:dns1] if network_config[:dns1]
                    xml.Dns2 network_config[:dns2] if network_config[:dns2]
                    xml.DnsSuffix network_config[:dns_suffix] if network_config[:dns_suffix]
                    xml.IpRanges {
                      xml.IpRange {
                        xml.StartAddress network_config[:start_address]
                        xml.EndAddress network_config[:end_address]
                      }
                    }
                  }
                }
                xml.ParentNetwork("href" => "#{@api_url}/network/#{network_config[:parent_network]}")
                xml.FenceMode network_config[:fence_mode]

                xml.Features {
                  xml.FirewallService {
                    xml.IsEnabled(network_config[:enable_firewall] || "false")
                  }
                }
              }
            }
          }
        }
        vm_list.each do |vm_name, vm_id|
          xml.SourcedItem {
            xml.Source("href" => "#{@api_url}/vAppTemplate/vm-#{vm_id}", "name" => vm_name)
            xml.InstantiationParams {
              xml.NetworkConnectionSection(
                "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1",
                "type" => "application/vnd.vmware.vcloud.networkConnectionSection+xml",
                "href" => "#{@api_url}/vAppTemplate/vm-#{vm_id}/networkConnectionSection/") {     
                  xml['ovf'].Info "Network config for sourced item"
                  xml.PrimaryNetworkConnectionIndex "0"
                  xml.NetworkConnection("network" => network_config[:name]) {
                    xml.NetworkConnectionIndex "0"
                    xml.IsConnected "true"
                    xml.IpAddressAllocationMode(network_config[:ip_allocation_mode] || "POOL")
                }
              }
            }
            xml.NetworkAssignment("containerNetwork" => network_config[:name], "innerNetwork" => network_config[:name])
          }
        end
        xml.AllEULAsAccepted "true"
      }
      end

      params = {
        "method" => :post,
        "command" => "/vdc/#{vdc}/action/composeVApp"
      }

      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.composeVAppParams+xml")

      vapp_id = headers[:location].gsub("#{@api_url}/vApp/vapp-", "")

      task = response.css("VApp Task[operationName='vdcComposeVapp']").first
      task_id = task["href"].gsub("#{@api_url}/task/", "")

      { :vapp_id => vapp_id, :task_id => task_id }
    end

    # Fetch details about a given vapp template:
    # - name
    # - description
    # - Children VMs:
    #   -- ID
    def get_vapp_template(vAppId)
      params = {
        'method' => :get,
        'command' => "/vAppTemplate/vappTemplate-#{vAppId}"
      }

      response, headers = send_request(params)

      vapp_node = response.css('VAppTemplate').first
      if vapp_node
        name = vapp_node['name']
        status = convert_vapp_status(vapp_node['status'])
      end

      description = response.css("Description").first
      description = description.text unless description.nil?

      ip = response.css('IpAddress').first
      ip = ip.text unless ip.nil?

      vms = response.css('Children Vm')
      vms_hash = {}

      vms.each do |vm|
        vms_hash[vm['name']] = {
          :id => vm['href'].gsub("#{@api_url}/vAppTemplate/vm-", '')
        }
      end

      # TODO: EXPAND INFO FROM RESPONSE
      { :name => name, :description => description, :vms_hash => vms_hash }
    end

    ##
    # Set vApp port forwarding rules
    # 
    # - vappid: id of the vapp to be modified
    # - network_name: name of the vapp network to be modified
    # - config: hash with network configuration specifications, must contain an array inside :nat_rules with the nat rules to be applied.
    def set_vapp_port_forwarding_rules(vappid, network_name, config={})
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.NetworkConfigSection(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5",
        "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1") {
        xml['ovf'].Info "Network configuration"
        xml.NetworkConfig("networkName" => network_name) {
          xml.Configuration {
            xml.ParentNetwork("href" => "#{@api_url}/network/#{config[:parent_network]}")
            xml.FenceMode(config[:fence_mode] || 'isolated')
            xml.Features {
              xml.NatService {
                xml.IsEnabled "true"
                xml.NatType "portForwarding"
                xml.Policy(config[:nat_policy_type] || "allowTraffic")
                config[:nat_rules].each do |nat_rule|
                  xml.NatRule {
                    xml.VmRule {
                      xml.ExternalPort nat_rule[:nat_external_port]
                      xml.VAppScopedVmId nat_rule[:vm_scoped_local_id]
                      xml.VmNicId(nat_rule[:nat_vmnic_id] || "0")
                      xml.InternalPort nat_rule[:nat_internal_port]
                      xml.Protocol(nat_rule[:nat_protocol] || "TCP")
                    }
                  }
                end
              }
            }
          }
        }
      }
      end

      params = {
        'method' => :put,
        'command' => "/vApp/vapp-#{vappid}/networkConfigSection"
      }

      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.networkConfigSection+xml")

      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

  
    ##
    # get vApp edge public IP from the vApp ID
    # Only works when: 
    # - vApp needs to be poweredOn
    # - FenceMode is set to "natRouted"
    # - NatType" is set to "portForwarding
    # This will be required to know how to connect to VMs behind the Edge device.
    def get_vapp_edge_public_ip(vAppId)

      # first check that vApp is running (Edge is created on vApp Power On)
      vApp = get_vapp(vAppId)
    
      if vApp[:status] == 'running'
        # Check the network configuration section
        params = {
          'method' => :get,
          'command' => "/vApp/vapp-#{vAppId}/networkConfigSection"
        }

        response, headers = send_request(params)

        # FIXME: this will return nil if the vApp uses multiple vApp Networks
        # with Edge devices in natRouted/portForwarding mode.

        fenceMode = response.css('NetworkConfigSection/NetworkConfig/Configuration/FenceMode').text
        natType = response.css('NetworkConfigSection/NetworkConfig/Configuration/Features/NatService/NatType').text

        if fenceMode == "natRouted" && natType == "portForwarding"
          # Check the routerInfo configuration where the global external IP is displayed
          edgeIp = response.css('NetworkConfigSection/NetworkConfig/Configuration/RouterInfo/ExternalIp')
          edgeIp = edgeIp.text unless edgeIp.nil?
        end
      end
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
      status, errormsg, start_time, end_time, response = nil
      loop do
        task = get_task(taskid)
        break if task[:status] != 'running'
        sleep 1
      end

      if status == 'error'
        errormsg = response.css("Error").first
        errormsg = "Error code #{errormsg['majorErrorCode']} - #{errormsg['message']}"
      end

      { :status => status, :errormsg => errormsg, :start_time => start_time, :end_time => end_time }
    end

    ##
    # Set vApp Network Config
    def set_vapp_network_config(vappid, network_name, config={})
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.NetworkConfigSection(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5",
        "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1") {
        xml['ovf'].Info "Network configuration"
        xml.NetworkConfig("networkName" => network_name) {
          xml.Configuration {
            xml.FenceMode(config[:fence_mode] || 'isolated')
            xml.RetainNetInfoAcrossDeployments(config[:retain_net] || false)
            xml.ParentNetwork("href" => config[:parent_network])
          }
        }
      }
      end

      params = {
        'method' => :put,
        'command' => "/vApp/vapp-#{vappid}/networkConfigSection"
      }

      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.networkConfigSection+xml")

      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

    ##
    # Set VM Network Config
    def set_vm_network_config(vmid, network_name, config={})
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.NetworkConnectionSection(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5",
        "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1") {
        xml['ovf'].Info "VM Network configuration"
        xml.PrimaryNetworkConnectionIndex(config[:primary_index] || 0)
        xml.NetworkConnection("network" => network_name, "needsCustomization" => true) {
          xml.NetworkConnectionIndex(config[:network_index] || 0)
          xml.IpAddress config[:ip] if config[:ip]
          xml.IsConnected(config[:is_connected] || true)
          xml.IpAddressAllocationMode config[:ip_allocation_mode] if config[:ip_allocation_mode]
        }
      }
      end

      params = {
        'method' => :put,
        'command' => "/vApp/vm-#{vmid}/networkConnectionSection"
      }

      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.networkConnectionSection+xml")

      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end


    ##
    # Set VM Guest Customization Config
    def set_vm_guest_customization(vmid, computer_name, config={})
      builder = Nokogiri::XML::Builder.new do |xml|
      xml.GuestCustomizationSection(
        "xmlns" => "http://www.vmware.com/vcloud/v1.5",
        "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1") {
          xml['ovf'].Info "VM Guest Customization configuration"
          xml.Enabled config[:enabled] if config[:enabled]
          xml.AdminPasswordEnabled config[:admin_passwd_enabled] if config[:admin_passwd_enabled]
          xml.AdminPassword config[:admin_passwd] if config[:admin_passwd]
          xml.ComputerName computer_name
      }
      end

      params = {
        'method' => :put,
        'command' => "/vApp/vm-#{vmid}/guestCustomizationSection"
      }

      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.guestCustomizationSection+xml")

      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

    ##
    # Fetch details about a given VM
    def get_vm(vmId)
      params = {
        'method' => :get,
        'command' => "/vApp/vm-#{vmId}"
      }

      response, headers = send_request(params)

      os_desc = response.css('ovf|OperatingSystemSection ovf|Description').first.text

      networks = {}
      response.css('NetworkConnection').each do |network|
        ip = network.css('IpAddress').first
        ip = ip.text if ip

        networks[network['network']] = {
          :index => network.css('NetworkConnectionIndex').first.text,
          :ip => ip,
          :is_connected => network.css('IsConnected').first.text,
          :mac_address => network.css('MACAddress').first.text,
          :ip_allocation_mode => network.css('IpAddressAllocationMode').first.text
        }
      end

      admin_password = response.css('GuestCustomizationSection AdminPassword').first
      admin_password = admin_password.text if admin_password

      guest_customizations = {
        :enabled => response.css('GuestCustomizationSection Enabled').first.text,
        :admin_passwd_enabled => response.css('GuestCustomizationSection AdminPasswordEnabled').first.text,
        :admin_passwd_auto => response.css('GuestCustomizationSection AdminPasswordAuto').first.text,
        :admin_passwd => admin_password,
        :reset_passwd_required => response.css('GuestCustomizationSection ResetPasswordRequired').first.text,
        :computer_name => response.css('GuestCustomizationSection ComputerName').first.text
      }

      { :os_desc => os_desc, :networks => networks, :guest_customizations => guest_customizations }
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
            raise InvalidStateError, "Invalid request because vApp is running. Stop vApp '#{$1}' and try again."
          when /The requested operation could not be executed since vApp "(.*)" is not running/
            raise InvalidStateError, "Invalid request because vApp is stopped. Start vApp '#{$1}' and try again."
          else
            raise UnhandledError, "BadRequest - unhandled error: #{message}.\nPlease report this issue."
          end
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
  end # class
end
