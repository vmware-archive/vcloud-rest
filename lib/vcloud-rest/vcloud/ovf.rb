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
      descriptorUpload = response.css("Files Link [rel='upload:default']").first[:href].gsub("#{@host_url}/transfer/", "")
      transferGUID = descriptorUpload.gsub("/descriptor.ovf", "")

      ovfFileBasename = File.basename(ovfFile, ".ovf")
      ovfDir = File.dirname(ovfFile)

      # Send OVF Descriptor
      uploadURL = "/transfer/#{descriptorUpload}"
      uploadFile = "#{ovfDir}/#{ovfFileBasename}.ovf"
      upload_file(uploadURL, uploadFile, vAppTemplate, uploadOptions)

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
          upload_file(uploadURL, uploadFile, vAppTemplate, uploadOptions)
          @logger.debug "OVF Manifest uploaded."
        end

        # Start uploading OVF VMDK files
        params = {
          'method' => :get,
          'command' => "/vAppTemplate/vappTemplate-#{vAppTemplate}"
        }
        response, headers = send_request(params)
        response.css("Files File [bytesTransferred='0'] Link [rel='upload:default']").each do |file|
          fileName = file[:href].gsub("#{@host_url}/transfer/#{transferGUID}/","")
          uploadFile = "#{ovfDir}/#{fileName}"
          uploadURL = "/transfer/#{transferGUID}/#{fileName}"
          upload_file(uploadURL, uploadFile, vAppTemplate, uploadOptions)
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
      ensure
        raise e
      end
    end

    private
      ##
      # Upload a large file in configurable chunks, output an optional progressbar
      def upload_file(uploadURL, uploadFile, vAppTemplate, config={})
        raise ::IOError, "#{uploadFile} not found." unless File.exists?(uploadFile)

        # Set chunksize to 10M if not specified otherwise
        chunkSize = (config[:chunksize] || 10485760)

        # Set progress bar to default format if not specified otherwise
        progressBarFormat = (config[:progressbar_format] || "%e <%B> %p%% %t")

        # Set progress bar length to 120 if not specified otherwise
        progressBarLength = (config[:progressbar_length] || 120)

        # Open our file for upload
        uploadFileHandle = File.new(uploadFile, "rb" )
        fileName = File.basename(uploadFileHandle)

        progressBarTitle = "Uploading: " + uploadFile.to_s

        # Create a progressbar object if progress bar is enabled
        if config[:progressbar_enable] == true && uploadFileHandle.size.to_i > chunkSize
          progressbar = ProgressBar.create(
            :title => progressBarTitle,
            :starting_at => 0,
            :total => uploadFileHandle.size.to_i,
            :length => progressBarLength,
            :format => progressBarFormat
          )
        else
          @logger.info progressBarTitle
        end
        # Create a new HTTP client
        clnt = HTTPClient.new

        # Disable SSL cert verification
        clnt.ssl_config.verify_mode=(OpenSSL::SSL::VERIFY_NONE)

        # Suppress SSL depth message
        clnt.ssl_config.verify_callback=proc{ |ok, ctx|; true };

        # Perform ranged upload until the file reaches its end
        until uploadFileHandle.eof?

          # Create ranges for this chunk upload
          rangeStart = uploadFileHandle.pos
          rangeStop = uploadFileHandle.pos.to_i + chunkSize

          # Read current chunk
          fileContent = uploadFileHandle.read(chunkSize)

          # If statement to handle last chunk transfer if is > than filesize
          if rangeStop.to_i > uploadFileHandle.size.to_i
            contentRange = "bytes #{rangeStart.to_s}-#{uploadFileHandle.size.to_s}/#{uploadFileHandle.size.to_s}"
            rangeLen = uploadFileHandle.size.to_i - rangeStart.to_i
          else
            contentRange = "bytes #{rangeStart.to_s}-#{rangeStop.to_s}/#{uploadFileHandle.size.to_s}"
            rangeLen = rangeStop.to_i - rangeStart.to_i
          end

          # Build headers
          extheader = {
            'x-vcloud-authorization' => @auth_key,
            'Content-Range' => contentRange,
            'Content-Length' => rangeLen.to_s
          }

          begin
            uploadRequest = "#{@host_url}#{uploadURL}"
            connection = clnt.request('PUT', uploadRequest, nil, fileContent, extheader)

            if config[:progressbar_enable] == true && uploadFileHandle.size.to_i > chunkSize
              params = {
                'method' => :get,
                'command' => "/vAppTemplate/vappTemplate-#{vAppTemplate}"
              }
              response, headers = send_request(params)

              response.css("Files File [name='#{fileName}']").each do |file|
                progressbar.progress=file[:bytesTransferred].to_i
              end
            end
          rescue
            retryTime = (config[:retry_time] || 5)
            @logger.warn "Range #{contentRange} failed to upload, retrying the chunk in #{retryTime.to_s} seconds, to stop the action press CTRL+C."
            sleep retryTime.to_i
            retry
          end
        end
        uploadFileHandle.close
      end
  end
end