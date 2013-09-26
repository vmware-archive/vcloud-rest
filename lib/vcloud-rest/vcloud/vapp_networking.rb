module VCloudClient
  class Connection
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
    # Get vApp port forwarding rules
    #
    # - vappid: id of the vApp
    def get_vapp_port_forwarding_rules(vAppId)
      params = {
        'method' => :get,
        'command' => "/vApp/vapp-#{vAppId}/networkConfigSection"
      }

      response, headers = send_request(params)

      # FIXME: this will return nil if the vApp uses multiple vApp Networks
      # with Edge devices in natRouted/portForwarding mode.
      config = response.css('NetworkConfigSection/NetworkConfig/Configuration')
      fenceMode = config.css('/FenceMode').text
      natType = config.css('/Features/NatService/NatType').text

      raise InvalidStateError, "Invalid request because FenceMode must be set to natRouted." unless fenceMode == "natRouted"
      raise InvalidStateError, "Invalid request because NatType must be set to portForwarding." unless natType == "portForwarding"

      nat_rules = {}
      config.css('/Features/NatService/NatRule').each do |rule|
        # portforwarding rules information
        ruleId = rule.css('Id').text
        vmRule = rule.css('VmRule')

        nat_rules[rule.css('Id').text] = {
          :ExternalIpAddress  => vmRule.css('ExternalIpAddress').text,
          :ExternalPort       => vmRule.css('ExternalPort').text,
          :VAppScopedVmId     => vmRule.css('VAppScopedVmId').text,
          :VmNicId            => vmRule.css('VmNicId').text,
          :InternalPort       => vmRule.css('InternalPort').text,
          :Protocol           => vmRule.css('Protocol').text
        }
      end
      nat_rules
    end

    ##
    # get vApp edge public IP from the vApp ID
    # Only works when:
    # - vApp needs to be poweredOn
    # - FenceMode is set to "natRouted"
    # - NatType" is set to "portForwarding
    # This will be required to know how to connect to VMs behind the Edge device.
    def get_vapp_edge_public_ip(vAppId)
      # Check the network configuration section
      params = {
        'method' => :get,
        'command' => "/vApp/vapp-#{vAppId}/networkConfigSection"
      }

      response, headers = send_request(params)

      # FIXME: this will return nil if the vApp uses multiple vApp Networks
      # with Edge devices in natRouted/portForwarding mode.
      config = response.css('NetworkConfigSection/NetworkConfig/Configuration')

      fenceMode = config.css('/FenceMode').text
      natType = config.css('/Features/NatService/NatType').text

      raise InvalidStateError, "Invalid request because FenceMode must be set to natRouted." unless fenceMode == "natRouted"
      raise InvalidStateError, "Invalid request because NatType must be set to portForwarding." unless natType == "portForwarding"

      # Check the routerInfo configuration where the global external IP is defined
      edgeIp = config.css('/RouterInfo/ExternalIp')
      edgeIp = edgeIp.text unless edgeIp.nil?
    end
  end
end