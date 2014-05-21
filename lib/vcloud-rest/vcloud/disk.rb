module VCloudClient
  class Connection

    def create_disk(name, size, vdc_id, description="")

      builder = Nokogiri::XML::Builder.new do |xml|
        xml.DiskCreateParams(
          "xmlns" => "http://www.vmware.com/vcloud/v1.5") {
          xml.Disk("name" => name, "size" => size) {
            xml.Description description
          }
        }
      end

      params = {
        'method' => :post,
        'command' => "/vdc/#{vdc_id}/disk"
      }

      @logger.debug "Creating independent disk #{name} in VDC #{vdc_id}"
      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.diskCreateParams+xml")

      # Get the id of the new disk
      disk_url = response.css("Disk").first[:href]
      disk_id = disk_url.gsub(/.*\/disk\//, "")
      @logger.debug "Independent disk created = #{disk_id}"

      task = response.css("Task[operationName='vdcCreateDisk']").first
      task_id = task["href"].gsub(/.*\/task\//, "")

      { :disk_id => disk_id, :task_id => task_id }
    end

    def get_disk(disk_id)

      params = {
        'method' => :get,
        'command' => "/disk/#{disk_id}"
      }

      @logger.debug "Fetching independent disk #{disk_id}"
      response, headers = send_request(params)

      name = response.css("Disk").attribute("name").text
      size = response.css("Disk").attribute("size").text
      description = response.css("Description").first
      description = description.text unless description.nil?
      storage_profile = response.css("StorageProfile").first[:name]
      owner = response.css("User").first[:name]
      { :id => disk_id, :name => name, :size => size, :description => description, :storage_profile => storage_profile, :owner => owner }
    end

    def get_disk_by_name(organization, vdcName, diskName)
      result = nil

      get_vdc_by_name(organization, vdcName)[:disks].each do |disk|
        if disk[0].downcase == diskName.downcase
          result = get_disk(disk[1])
        end
      end

      result
    end

    def attach_disk_to_vm(disk_id, vm_id)
      disk_attach_action(disk_id, vm_id, 'attach')
    end

    def detach_disk_from_vm(disk_id, vm_id)
      disk_attach_action(disk_id, vm_id, 'detach')
    end

    def delete_disk(disk_id)
      params = {
        'method' => :delete,
        'command' => "/disk/#{disk_id}"
      }

      @logger.debug "Deleting independent disk #{disk_id}"
      response, headers = send_request(params)

      task = response.css("Task").first
      task_id = task["href"].gsub(/.*\/task\//, "")      
    end

    private

    def disk_attach_action(disk_id, vm_id, action)
      builder = Nokogiri::XML::Builder.new do |xml|
        xml.DiskAttachOrDetachParams("xmlns" => "http://www.vmware.com/vcloud/v1.5") {
          xml.Disk(
            "type" => "application/vnd.vmware.vcloud.disk+xml",
            "href" => "#{@api_url}/disk/#{disk_id}")
        }
      end

      params = {
        'method' => :post,
        'command' => "/vApp/vm-#{vm_id}/disk/action/#{action}"
      }
      
      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.diskAttachOrDetachParams+xml")

      task = response.css("Task").first
      task_id = task["href"].gsub(/.*\/task\//, "")
    end

  end
end