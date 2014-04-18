module VCloudClient
  class Connection

    def upload_media(vdcId, mediaName, mediaDescription, mediaFile, catalogId, uploadOptions={})
      raise ::IOError, "File #{mediaFile} is missing." unless File.exists?(mediaFile)

      # Going to assume media files are isos, because the only other thing allowed is floppies
      type = "iso"
      fileName = File.basename(mediaFile)
      mediaName = File.basename(fileName, ".iso") if mediaName.nil? || mediaName.empty?
      size = File.size(mediaFile)

      builder = Nokogiri::XML::Builder.new do |xml|
        xml.Media(
          "xmlns" => "http://www.vmware.com/vcloud/v1.5",
          "xmlns:ovf" => "http://schemas.dmtf.org/ovf/envelope/1",
          "size" => size,
          "imageType" => type,
          "name" => mediaName) {
            xml.Description mediaDescription
          }
      end

      params = {
        'method' => :post,
        'command' => "/vdc/#{vdcId}/media"
      }

      @logger.debug "Creating Media item"
      response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.media+xml")

      # Get the new media id from response
      mediaUrl = response.css("Media").first[:href]
      mediaId = mediaUrl.gsub(/.*\/media\//, "")
      @logger.debug "Media item created - #{mediaId}"

      # Get File upload:default link from response
      uploadHref = response.css("Files Link [rel='upload:default']").first[:href]
      fileUpload = uploadHref.gsub(/(.*)(\/transfer\/.*)/, "\\2")

      begin
        @logger.debug "Uploading #{mediaFile}"
        upload_file(fileUpload, mediaFile, "/media/#{mediaId}")

        # Add item to the catalog catalogId
        builder = Nokogiri::XML::Builder.new do |xml|
          xml.CatalogItem(
            "xmlns" => "http://www.vmware.com/vcloud/v1.5",
            "type" => "application/vnd.vmware.vcloud.catalogItem+xml",
            "name" => mediaName) {
            xml.Description mediaDescription
            xml.Entity("href" => "#{@api_url}/media/#{mediaId}")
          }
        end

        params = {
          'method' => :post,
          'command' => "/catalog/#{catalogId}/catalogItems"
        }

        @logger.debug "Adding media item #{mediaName} to catalog."
        response, headers = send_request(params, builder.to_xml, "application/vnd.vmware.vcloud.catalogItem+xml")

        # TODO: the best thing would detect the real importing status.
        entity = response.css("Entity").first
        result = {}
        if entity
          result[:id] = entity['href'].gsub(/.*\/media\//, "")
          result[:name] = entity['name']
        end
        result
      rescue Exception => e
        @logger.error "Exception detected: #{e.message}."

        # Get Media Task
        params = {
          'method' => :get,
          'command' => "/media/#{mediaId}"
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
  end
end