module VCloudClient
  class Connection
    ##
    # Set vApp Network Config
    #
    # Retrieve the existing network config section and edit it
    # to ensure settings are not lost
    def set_vapp_network_config(vappid, network, config={})
      params = {
        'method' => :get,
        'command' => "/vApp/vapp-#{vappid}/networkConfigSection"
      }

      netconfig_response, headers = send_request(params)

      picked_network = netconfig_response.css("NetworkConfig").select do |net|
        net.attribute('networkName').text == network[:name]
      end.first

      raise WrongItemIDError, "Network named #{network[:name]} not found." unless picked_network

      picked_network.css('FenceMode').first.content = config[:fence_mode] if config[:fence_mode]
      picked_network.css('IsInherited').first.content = "true"
      picked_network.css('RetainNetInfoAcrossDeployments').first.content = config[:retain_network] if config[:retain_network]

      if config[:parent_network]
        parent_network = picked_network.css('ParentNetwork').first
        new_parent = false

        unless parent_network
          new_parent = true
          ipscopes = picked_network.css('IpScopes').first
          parent_network = Nokogiri::XML::Node.new "ParentNetwork", ipscopes.parent
        end

        parent_network["name"] = "#{config[:parent_network][:name]}"
        parent_network["id"] = "#{config[:parent_network][:id]}"
        parent_network["href"] = "#{@api_url}/admin/network/#{config[:parent_network][:id]}"
        ipscopes.add_next_sibling(parent_network) if new_parent
      end

      data = netconfig_response.to_xml

      params = {
        'method' => :put,
        'command' => "/vApp/vapp-#{vappid}/networkConfigSection"
      }

      response, headers = send_request(params, data, "application/vnd.vmware.vcloud.networkConfigSection+xml")

      task_id = headers[:location].gsub(/.*\/task\//, "")
      task_id
    end


    ##
    # Add an existing network (from Org) to vApp
    #
    #
    def add_org_network_to_vapp(vAppId, network, config)
      network_section = generate_network_section(vAppId, network, config, :external)
      add_network_to_vapp(vAppId, network_section)
    end

    ##
    # Add an existing network (from Org) to vApp
    def add_internal_network_to_vapp(vAppId, network, config)
      network_section = generate_network_section(vAppId, network, config, :internal)
      add_network_to_vapp(vAppId, network_section)
    end

    ##
    # Remove an existing network
    def delete_vapp_network(vAppId, network)
      params = {
        'method' => :get,
        'command' => "/vApp/vapp-#{vAppId}/networkConfigSection"
      }

      netconfig_response, headers = send_request(params)

      picked_network = netconfig_response.css("NetworkConfig").select do |net|
        net.attribute('networkName').text == network[:name]
      end.first

      raise WrongItemIDError, "Network #{network[:name]} not found on this vApp." unless picked_network

      picked_network.remove

      params = {
        'method' => :put,
        'command' => "/vApp/vapp-#{vAppId}/networkConfigSection"
      }

      put_response, headers = send_request(params, netconfig_response.to_xml, "application/vnd.vmware.vcloud.networkConfigSection+xml")

      task_id = headers[:location].gsub(/.*\/task\//, "")
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

      task_id = headers[:location].gsub(/.*\/task\//, "")
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

    private
      ##
      # Merge the Configuration section of a new network and add specific configuration
      def merge_network_config(vapp_networks, new_network, config)
        net_configuration = new_network.css('Configuration').first

        fence_mode = new_network.css('FenceMode').first
        fence_mode.content = config[:fence_mode] || 'isolated'

        network_features = Nokogiri::XML::Node.new "Features", net_configuration
        firewall_service = Nokogiri::XML::Node.new "FirewallService", network_features
        firewall_enabled = Nokogiri::XML::Node.new "IsEnabled", firewall_service
        firewall_enabled.content = config[:firewall_enabled] || "false"

        firewall_service.add_child(firewall_enabled)
        network_features.add_child(firewall_service)
        net_configuration.add_child(network_features)

        if config[:parent_network]
          # At this stage, set itself as parent network
          parent_network = Nokogiri::XML::Node.new "ParentNetwork", net_configuration
          parent_network["href"] = "#{@api_url}/network/#{config[:parent_network][:id]}"
          parent_network["name"] = config[:parent_network][:name]
          parent_network["type"] = "application/vnd.vmware.vcloud.network+xml"
          new_network.css('IpScopes').first.add_next_sibling(parent_network)
        end

        vapp_networks.to_xml.gsub("<PLACEHOLDER/>", new_network.css('Configuration').to_xml)
      end

      ##
      # Add a new network to a vApp
      def add_network_to_vapp(vAppId, network_section)
        params = {
          'method' => :put,
          'command' => "/vApp/vapp-#{vAppId}/networkConfigSection"
        }

        response, headers = send_request(params, network_section, "application/vnd.vmware.vcloud.networkConfigSection+xml")

        task_id = headers[:location].gsub(/.*\/task\//, "")
        task_id
      end

      ##
      # Create a fake NetworkConfig node whose content will be replaced later
      #
      # Note: this is a hack to avoid wrong merges through Nokogiri
      # that would add a default: namespace
      def create_fake_network_node(vapp_networks, network_name)
        parent_section = vapp_networks.css('NetworkConfigSection').first
        new_network = Nokogiri::XML::Node.new "NetworkConfig", parent_section
        new_network['networkName'] = network_name
        placeholder = Nokogiri::XML::Node.new "PLACEHOLDER", new_network
        new_network.add_child placeholder
        parent_section.add_child(new_network)
        vapp_networks
      end

      ##
      # Create a fake Configuration node for internal networking
      def create_internal_network_node(network_config)
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.Configuration {
            xml.IpScopes {
              xml.IpScope {
                xml.IsInherited(network_config[:is_inherited] || "false")
                xml.Gateway network_config[:gateway]
                xml.Netmask network_config[:netmask]
                xml.Dns1 network_config[:dns1] if network_config[:dns1]
                xml.Dns2 network_config[:dns2] if network_config[:dns2]
                xml.DnsSuffix network_config[:dns_suffix] if network_config[:dns_suffix]
                xml.IsEnabled(network_config[:is_enabled] || true)
                xml.IpRanges {
                  xml.IpRange {
                    xml.StartAddress network_config[:start_address]
                    xml.EndAddress network_config[:end_address]
                  }
                }
              }
            }
            xml.FenceMode 'isolated'
            xml.RetainNetInfoAcrossDeployments(network_config[:retain_info] || false)
          }
        end
        builder.doc
      end

      ##
      # Create a NetworkConfigSection for a new internal or external network
      def generate_network_section(vAppId, network, config, type)
        params = {
          'method' => :get,
          'command' => "/vApp/vapp-#{vAppId}/networkConfigSection"
        }

        vapp_networks, headers = send_request(params)
        create_fake_network_node(vapp_networks, network[:name])

        if type.to_sym == :internal
          # Create a network configuration based on the config
          new_network = create_internal_network_node(config)
        else
          # Retrieve the requested network and prepare it for customization
          new_network = get_base_network(network[:id])
        end

        merge_network_config(vapp_networks, new_network, config)
      end
  end
end
