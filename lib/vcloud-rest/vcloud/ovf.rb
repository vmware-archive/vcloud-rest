module VCloudClient
  class Connection
    ##
    # Upload an OVF package
    # - vdcId
    # - vappName
    # - vappDescription
    # - ovfFile
    # - catalogId
    # - uploadOptions {}
    def upload_ovf(vdcId, vappName, vappDescription, ovfFile, catalogId, uploadOptions={})
      raise ::IOError, "OVF #{ovfFile} is missing." unless File.exists?(ovfFile)

      # if send_manifest is not set, setting it true
      if uploadOptions[:send_manifest].nil? || uploadOptions[:send_manifest]
        uploadManifest = "true"
      else
        uploadManifest = "false"
      end

      builder = Nokogiri::XML::Builder.new do |xml|
        xml.UploadVAppTemplateParams(
          "xmlns" => "http://www.vmware.com/vcloud/v1.5",
          "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1",
          "manifestRequired" => uploadManifest,
          "name" => vappName) {
          xml.Description vappDescription
        }
      end

      params = {
        'method' => :post,
        'command' => "/vdc/#{vdcId}/action/uploadVAppTemplate"
      }

      response, headers = send_request(
        params,
        builder.to_xml,
        "application/vnd.vmware.vcloud.uploadVAppTemplateParams+xml"
      )

      # Get vAppTemplate Link from location
      vAppTemplate = headers[:location].gsub(/.*\/vAppTemplate\/vappTemplate\-/, "")
      uploadHref = response.css("Files Link [rel='upload:default']").first[:href]
      descriptorUpload = uploadHref.gsub(/.*\/transfer\//, "")

      transferGUID = descriptorUpload.gsub("/descriptor.ovf", "")

      ovfFileBasename = File.basename(ovfFile, ".ovf")
      ovfDir = File.dirname(ovfFile)

      # Send OVF Descriptor
      uploadURL = "/transfer/#{descriptorUpload}"
      uploadFile = "#{ovfDir}/#{ovfFileBasename}.ovf"
      upload_file(uploadURL, uploadFile, "/vAppTemplate/vappTemplate-#{vAppTemplate}", uploadOptions)

      @logger.debug "OVF Descriptor uploaded."

      # Begin the catch for upload interruption
      begin
        params = {
          'method' => :get,
          'command' => "/vAppTemplate/vappTemplate-#{vAppTemplate}"
        }

        # Loop to wait for the upload links to show up in the vAppTemplate we just created
        while true
          response, headers = send_request(params)

          errored_task = response.css("Tasks Task [status='error']").first
          if errored_task
            error_msg = errored_task.css('Error').first['message']
            raise OVFError, "OVF Upload failed: #{error_msg}"
          end

          break unless response.css("Files Link [rel='upload:default']").count == 1
          sleep 1
        end

        if uploadManifest == "true"
          uploadURL = "/transfer/#{transferGUID}/descriptor.mf"
          uploadFile = "#{ovfDir}/#{ovfFileBasename}.mf"
          upload_file(uploadURL, uploadFile, "/vAppTemplate/vappTemplate-#{vAppTemplate}", uploadOptions)
          @logger.debug "OVF Manifest uploaded."
        end

        # Start uploading OVF VMDK files
        params = {
          'method' => :get,
          'command' => "/vAppTemplate/vappTemplate-#{vAppTemplate}"
        }
        response, headers = send_request(params)
        response.css("Files File [bytesTransferred='0'] Link [rel='upload:default']").each do |file|
          fileName = file[:href].gsub(/.*\/transfer\/#{transferGUID}\//, "")
          uploadFile = "#{ovfDir}/#{fileName}"
          uploadURL = "/transfer/#{transferGUID}/#{fileName}"
          upload_file(uploadURL, uploadFile, "/vAppTemplate/vappTemplate-#{vAppTemplate}", uploadOptions)
        end

        # Add item to the catalog catalogId
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.CatalogItem(
            "xmlns" => "http://www.vmware.com/vcloud/v1.5",
            "type" => "application/vnd.vmware.vcloud.catalogItem+xml",
            "name" => vappName) {
            xml.Description vappDescription
            xml.Entity(
              "href" => "#{@api_url}/vAppTemplate/vappTemplate-#{vAppTemplate}"
              )
          }
        end

        params = {
          'method' => :post,
          'command' => "/catalog/#{catalogId}/catalogItems"
        }

        @logger.debug "Add item to catalog."
        response, headers = send_request(params, builder.to_xml,
                        "application/vnd.vmware.vcloud.catalogItem+xml")

        entity = response.css("Entity").first

        # TODO: the best thing would detect the real importing status.
        result = {}
        if entity
          result[:id] = entity['href'].gsub(/.*\/vAppTemplate\/vappTemplate\-/, "")
          result[:name] = entity['name']
        end
        result
      rescue Exception => e
        @logger.error "Exception detected: #{e.message}."

        # Get vAppTemplate Task
        params = {
          'method' => :get,
          'command' => "/vAppTemplate/vappTemplate-#{vAppTemplate}"
        }
        response, headers = send_request(params)

        # Cancel Task
        # Note that it might not exist (i.e., error for existing vdc entity)
        tasks = response.css("Tasks")
        unless tasks.empty?
          tasks.css("Task").each do |task|
            if task['status'] == 'error'
              @logger.error task.css('Error').first['message']
            else
              id = task['href'].gsub(/.*\/task\//, "")
              @logger.error "Aborting task #{id}..."
              cancel_task(id)
            end
          end
        end

        raise e
      end
    end
  end # class
end