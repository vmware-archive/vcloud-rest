module VCloudClient
  class Connection
    ##
    # Fetch details about a given Org VDC network
    def get_network(networkId)
      response = get_base_network(networkId)

      name = response.css('OrgVdcNetwork').attribute('name').text

      description = response.css("Description").first
      description = description.text unless description.nil?

      gateway = response.css('Gateway')
      gateway = gateway.text unless gateway.nil?

      netmask = response.css('Netmask')
      netmask = netmask.text unless netmask.nil?

      fence_mode = response.css('FenceMode')
      fence_mode = fence_mode.text unless fence_mode.nil?

      start_address = response.css('StartAddress')
      start_address = start_address.text unless start_address.nil?

      end_address = response.css('EndAddress')
      end_address = end_address.text unless end_address.nil?


      { :id => networkId, :name => name, :description => description,
        :gateway => gateway, :netmask => netmask, :fence_mode => fence_mode,
        :start_address => start_address, :end_address => end_address }
    end

    ##
    # Friendly helper method to fetch an network id by name
    # - organization hash (from get_organization/get_organization_by_name)
    # - network name
    def get_network_id_by_name(organization, networkName)
      result = nil

      organization[:networks].each do |network|
        if network[0].downcase == networkName.downcase
          result = network[1]
        end
      end

      result
    end

    ##
    # Friendly helper method to fetch an network by name
    # - organization hash (from get_organization/get_organization_by_name)
    # - network name
    def get_network_by_name(organization, networkName)
      result = nil

      organization[:networks].each do |network|
        if network[0].downcase == networkName.downcase
          result = get_network(network[1])
        end
      end

      result
    end

    private
      # Get a network configuration
      def get_base_network(networkId)
        params = {
          'method' => :get,
          'command' => "/network/#{networkId}"
        }

        base_network, headers = send_request(params)
        base_network
      end
  end
end