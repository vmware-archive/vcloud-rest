module VCloudClient
  class Connection
    ##
    # Fetch list of vSphere server references.
    def get_vimServers
      params = {
        'method'  => :get,
        'command' => "/admin/extension/vimServerReferences"
      }
      response, headers = send_request(params)

      vimServers = {}
      response.css("[type='application/vnd.vmware.admin.vmwvirtualcenter+xml']").each do |item|
        vimServers[item['name']] = item['href'].gsub(/.*\/vimServer\//, "")
      end

      vimServers
    end

    ##
    # Fetch all the hosts attached to VC
    def get_vimHosts(vimServerId)
      params = {
        'method'  => :get,
        'command' => "/admin/extension/vimServer/#{vimServerId}/hostReferences"
      }
      response, headers = send_request(params)

      hosts = {}
      response.css("[type='application/vnd.vmware.admin.host+xml']").each do |item|
        hosts[item['name']] = item['href'].gsub(/.*\/host\//, "")
      end

      hosts
    end

    ##
    # Fetch a host informations
    def get_HostInfo(hostId)
      items = ['Ready', 'Available', 'Enabled', 'Busy', 'EnableHostForHostSpanning', 'CpuType', 'NumOfCpusPackages', 'NumOfCpusLogical', 'CpuTotal', 'MemUsed', 'MemTotal' ,'HostOsName' , 'HostOsVersion', 'VmMoRef']
      params = {
        'method'  => :get,
        'command' => "/admin/extension/host/#{hostId}"
      }
      response, headers = send_request(params)

      hostInfo = {}
      items.each do |i|
        hostInfo[i] = response.xpath("//vmext:#{i}").text
      end

      hostInfo
    end
  end
end