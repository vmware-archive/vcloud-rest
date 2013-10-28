require 'vcloud-rest/vcloud/vapp_networking'

module VCloudClient
  class Connection
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

      networks = response.css('NetworkConfig').reject{|n| n.attribute('networkName').text == 'none'}.
        collect do |network|
          net_name = network.attribute('networkName').text

          gateway = network.css('Gateway')
          gateway = gateway.text unless gateway.nil?

          netmask = network.css('Netmask')
          netmask = netmask.text unless netmask.nil?

          fence_mode = network.css('FenceMode')
          fence_mode = fence_mode.text unless fence_mode.nil?

          parent_network = network.css('ParentNetwork')
          parent_network = parent_network.attribute('name').text unless parent_network.empty?
          parent_network = nil if parent_network.empty?

          retain_network = network.css('RetainNetInfoAcrossDeployments')
          retain_network = retain_network.text unless retain_network.nil?

          # TODO: handle multiple scopes?
          ipscope =  {
              :gateway => gateway,
              :netmask => netmask,
              :fence_mode => fence_mode,
              :parent_network => parent_network,
              :retain_network => retain_network
            }

          {
            :name => net_name,
            :scope => ipscope
          }
        end

      vms = response.css('Children Vm')
      vms_hash = {}

      vms.each do |vm|
        vapp_local_id = vm.css('VAppScopedLocalId')
        addresses = vm.css('rasd|Connection').collect do |n|
          address = n['vcloud:ipAddress']
          address = n.attributes['ipAddress'] unless address
          address = address.value if address
        end

        vms_hash[vm['name']] = {
          :addresses => addresses,
          :status => convert_vapp_status(vm['status']),
          :id => vm['href'].gsub(/.*\/vApp\/vm\-/, ""),
          :vapp_scoped_local_id => vapp_local_id.text
        }
      end

      { :id => vAppId, :name => name, :description => description,
        :status => status, :ip => ip, :networks => networks, :vms_hash => vms_hash }
    end

    ##
    # Friendly helper method to fetch a vApp by name
    # - Organization object
    # - Organization VDC Name
    # - vApp name
    def get_vapp_by_name(organization, vdcName, vAppName)
      result = nil

      get_vdc_by_name(organization, vdcName)[:vapps].each do |vapp|
        if vapp[0].downcase == vAppName.downcase
          result = get_vapp(vapp[1])
        end
      end

      result
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
      task_id = headers[:location].gsub(/.*\/task\//, "")
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
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end

    ##
    # Suspend a given vapp
    def suspend_vapp(vAppId)
      power_action(vAppId, 'suspend')
    end

    ##
    # reboot a given vapp
    # This will basically initial a guest OS reboot, and will only work if
    # VMware-tools are installed on the underlying VMs.
    # vShield Edge devices are not affected
    def reboot_vapp(vAppId)
      power_action(vAppId, 'reboot')
    end

    ##
    # reset a given vapp
    # This will basically reset the VMs within the vApp
    # vShield Edge devices are not affected.
    def reset_vapp(vAppId)
      power_action(vAppId, 'reset')
    end

    ##
    # Boot a given vapp
    def poweron_vapp(vAppId)
      power_action(vAppId, 'powerOn')
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

      vapp_id = headers[:location].gsub(/.*\/vApp\/vapp\-/, "")
      task = response.css("VApp Task[operationName='vdcInstantiateVapp']").first
      task_id = task["href"].gsub(/.*\/task\//, "")

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

      vapp_id = headers[:location].gsub(/.*\/vApp\/vapp\-/, "")

      task = response.css("VApp Task[operationName='vdcComposeVapp']").first
      task_id = task["href"].gsub(/.*\/task\//, "")

      { :vapp_id => vapp_id, :task_id => task_id }
    end

    ##
    # Create a new snapshot (overwrites any existing)
    def create_snapshot(vappId, description="New Snapshot")
      params = {
          "method" => :post,
          "command" => "/vApp/vapp-#{vappId}/action/createSnapshot"
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
    # Revert to an existing snapshot
    def revert_snapshot(vappId)
      params = {
          "method" => :post,
          "command" => "/vApp/vapp-#{vappId}/action/revertToCurrentSnapshot"
      }
      response, headers = send_request(params)
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end

    ##
    # Clone a vapp in a given VDC to a new Vapp
    def clone_vapp(vdc_id, source_vapp_id, name, deploy="true", poweron="false", linked="false", delete_source="false")
      params = {
          "method" => :post,
          "command" => "/vdc/#{vdc_id}/action/cloneVApp"
      }
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.CloneVAppParams(
            "xmlns" => "http://www.vmware.com/vcloud/v1.5",
            "name" => name,
            "deploy"=>  deploy,
            "linkedClone"=> linked,
            "powerOn"=> poweron
        ) {
          xml.Source "href" => "#{@api_url}/vApp/vapp-#{source_vapp_id}"
          xml.IsSourceDelete delete_source
        }
      end
      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.cloneVAppParams+xml")

      vapp_id = headers[:location].gsub(/.*\/vApp\/vapp\-/, "")

      task = response.css("VApp Task[operationName='vdcCopyVapp']").first
      task_id = task["href"].gsub(/.*\/task\//, "")

      {:vapp_id => vapp_id, :task_id => task_id}
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
          :id => vm['href'].gsub(/.*\/vAppTemplate\/vm\-/, "")
        }
      end

      { :name => name, :description => description, :vms_hash => vms_hash }
    end

    ##
    # Force a guest customization
    def force_customization_vapp(vappId)
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.DeployVAppParams(
          "xmlns" => "http://www.vmware.com/vcloud/v1.5",
          "forceCustomization" => "true")
      end

      params = {
        "method" => :post,
        "command" => "/vApp/vapp-#{vappId}/action/deploy"
      }

      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.deployVAppParams+xml")
      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end
  end
end
