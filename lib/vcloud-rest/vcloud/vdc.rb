module VCloudClient
  class Connection
    ##
    # Fetch details about a given vdc:
    # - description
    # - vapps
    # - templates
    # - disks
    # - networks
    def get_vdc(vdcId)
      params = {
        'method' => :get,
        'command' => "/vdc/#{vdcId}"
      }

      response, headers = send_request(params)

      name = response.css("Vdc").attribute("name")
      name = name.text unless name.nil?

      description = response.css("Description").first
      description = description.text unless description.nil?

      vapps = {}
      response.css("ResourceEntity[type='application/vnd.vmware.vcloud.vApp+xml']").each do |item|
        vapps[item['name']] = item['href'].gsub(/.*\/vApp\/vapp\-/, "")
      end

      templates = {}
      response.css("ResourceEntity[type='application/vnd.vmware.vcloud.vAppTemplate+xml']").each do |item|
        templates[item['name']] = item['href'].gsub(/.*\/vAppTemplate\/vappTemplate\-/, "")
      end

      disks = {}
      response.css("ResourceEntity[type='application/vnd.vmware.vcloud.disk+xml']").each do |item|
        disks[item['name']] = item['href'].gsub(/.*\/disk\//, "")
      end

      networks = {}
      response.css("Network[type='application/vnd.vmware.vcloud.network+xml']").each do |item|
        networks[item['name']] = item['href'].gsub(/.*\/network\//, "")
      end

      { :id => vdcId, :name => name, :description => description,
        :vapps => vapps, :templates => templates, :disks => disks,
        :networks => networks }
    end

    ##
    # Friendly helper method to fetch a Organization VDC Id by name
    # - Organization object
    # - Organization VDC Name
    def get_vdc_id_by_name(organization, vdcName)
      result = nil

      organization[:vdcs].each do |vdc|
        if vdc[0].downcase == vdcName.downcase
          result = vdc[1]
        end
      end

      result
    end

    ##
    # Friendly helper method to fetch a Organization VDC by name
    # - Organization object
    # - Organization VDC Name
    def get_vdc_by_name(organization, vdcName)
      result = nil

      organization[:vdcs].each do |vdc|
        if vdc[0].downcase == vdcName.downcase
          result = get_vdc(vdc[1])
        end
      end

      result
    end
  end
end