module VCloudClient
  class Connection
    ##
    # Retrieve information (i.e., memory and CPUs)
    def get_vm_info(vmid)
      params = {
        'method' => :get,
        'command' => "/vApp/vm-#{vmid}/virtualHardwareSection"
      }

      response, headers = send_request(params)

      result = {}
      response.css("ovf|Item [vcloud|href]").each do |item|
        item_name = item.attribute('href').text.gsub("#{@api_url}/vApp/vm-#{vmid}/virtualHardwareSection/", "")
        name = item.css("rasd|ElementName")
        name = name.text unless name.nil?

        description = item.css("rasd|Description")
        description = description.text unless description.nil?

        result[item_name] = {
          :name => name,
          :description => description
        }
      end

      result
    end

    ##
    # Retrieve information about Disks
    def get_vm_disk_info(vmid)
      response, headers = __get_disk_info(vmid)

      disks = []
      response.css("Item").each do |entry|
        # Pick only entries with node "HostResource"
        resource = entry.css("rasd|HostResource").first
        next unless resource

        name = entry.css("rasd|ElementName").first
        name = name.text unless name.nil?
        capacity = resource.attribute("capacity").text

        disks << {
          :name => name,
          :capacity => "#{capacity} MB"
        }
      end
      disks
    end

    ##
    # Set information about Disks
    #
    # Disks can be added, deleted or modified
    def set_vm_disk_info(vmid, disk_info={})
      get_response, headers = __get_disk_info(vmid)

      if disk_info[:add]
        data = add_disk(get_response, disk_info)
      else
        data = edit_disk(get_response, disk_info)
      end

      params = {
        'method' => :put,
        'command' => "/vApp/vm-#{vmid}/virtualHardwareSection/disks"
      }
      put_response, headers = send_request(params, data, "application/vnd.vmware.vcloud.rasdItemsList+xml")

      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

    ##
    # Set VM CPUs
    def set_vm_cpus(vmid, cpu_number)
      params = {
        'method' => :get,
        'command' => "/vApp/vm-#{vmid}/virtualHardwareSection/cpu"
      }

      get_response, headers = send_request(params)

      # Change attributes from the previous invocation
      get_response.css("rasd|ElementName").first.content = "#{cpu_number} virtual CPU(s)"
      get_response.css("rasd|VirtualQuantity").first.content = cpu_number

      params['method'] = :put
      put_response, headers = send_request(params, get_response.to_xml, "application/vnd.vmware.vcloud.rasdItem+xml")

      task_id = headers[:location].gsub("#{@api_url}/task/", "")
      task_id
    end

    ##
    # Set VM RAM
    def set_vm_ram(vmid, memory_size)
      params = {
        'method' => :get,
        'command' => "/vApp/vm-#{vmid}/virtualHardwareSection/memory"
      }

      get_response, headers = send_request(params)

      # Change attributes from the previous invocation
      get_response.css("rasd|ElementName").first.content = "#{memory_size} MB of memory"
      get_response.css("rasd|VirtualQuantity").first.content = memory_size

      params['method'] = :put
      put_response, headers = send_request(params, get_response.to_xml, "application/vnd.vmware.vcloud.rasdItem+xml")

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

      vm_name = response.css('Vm').attribute("name")
      vm_name = vm_name.text unless vm_name.nil?

      status = convert_vapp_status(response.css('Vm').attribute("status").text)

      os_desc = response.css('ovf|OperatingSystemSection ovf|Description').first.text

      networks = {}
      response.css('NetworkConnection').each do |network|
        ip = network.css('IpAddress').first
        ip = ip.text if ip

        external_ip = network.css('ExternalIpAddress').first
        external_ip = external_ip.text if external_ip

        networks[network['network']] = {
          :index => network.css('NetworkConnectionIndex').first.text,
          :ip => ip,
          :external_ip => external_ip,
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
        :reset_passwd_required => response.css('GuestCustomizationSection ResetPasswordRequired').first.text
      }

      { :id => vmId,
        :vm_name => vm_name, :os_desc => os_desc, :networks => networks,
        :guest_customizations => guest_customizations, :status => status }
    end

    ##
    # Friendly helper method to fetch a vApp by name
    # - Organization object
    # - Organization VDC Name
    # - vApp Name
    # - VM Name
    def get_vm_by_name(organization, vdcName, vAppName, vmName)
      result = nil

      puts get_vapp_by_name(organization, vdcName, vAppName)
      get_vapp_by_name(organization, vdcName, vAppName)[:vms_hash].each do |key, values|
        if key.downcase == vmName.downcase
          result = get_vm(values[:id])
        end
      end

      result
    end

    private
      def add_disk(source_xml, disk_info)
        disks_count = source_xml.css("Item").css("rasd|HostResource").count

        # FIXME: This is a hack, but dealing with nokogiri APIs can be quite
        # frustrating sometimes...
        sibling = source_xml.css("Item").first
        new_disk = Nokogiri::XML::Node.new "PLACEHOLDER", sibling.parent
        sibling.add_next_sibling(new_disk)
        result = source_xml.to_xml

        result.gsub("<PLACEHOLDER/>", """
          <Item>
            <rasd:AddressOnParent>#{disks_count}</rasd:AddressOnParent>
            <rasd:Description>Hard disk</rasd:Description>
            <rasd:ElementName>Hard disk #{disks_count + 1}</rasd:ElementName>
            <rasd:HostResource
                  xmlns:ns12=\"http://www.vmware.com/vcloud/v1.5\"
                  ns12:capacity=\"#{disk_info[:disk_size]}\"
                  ns12:busSubType=\"lsilogic\"
                  ns12:busType=\"6\"/>
            <rasd:InstanceID>200#{disks_count}</rasd:InstanceID>
            <rasd:Parent>1</rasd:Parent>
            <rasd:ResourceType>17</rasd:ResourceType>
          </Item>""")
      end

      def edit_disk(source_xml, disk_info)
        changed = false

        source_xml.css("Item").each do |entry|
          # Pick only entries with node "HostResource"
          resource = entry.css("rasd|HostResource").first
          next unless resource

          name = entry.css("rasd|ElementName").first
          name = name.text unless name.nil?
          next unless name == disk_info[:disk_name]

          changed = true

          if disk_info[:delete]
            entry.remove
          else
            # Set disk size
            resource.attribute("capacity").content = disk_info[:disk_size]
          end
          break
        end

        unless changed
          @logger.warn "Disk #{disk_info[:disk_name]} not found."
          raise WrongItemIDError, "Disk #{disk_info[:disk_name]} not found."
        end
        source_xml.to_xml
      end

      def __get_disk_info(vmid)
        params = {
          'method' => :get,
          'command' => "/vApp/vm-#{vmid}/virtualHardwareSection/disks"
        }

        send_request(params)
      end
  end
end