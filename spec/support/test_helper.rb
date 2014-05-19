## Support for 1.8.x
unless Kernel.respond_to?(:require_relative)
  module Kernel
    def require_relative(path)
      require File.join(File.dirname(caller[0]), path.to_str)
    end
  end
end
##

require 'minitest/autorun'
require 'minitest/spec'
require 'webmock/minitest'
require_relative '../../lib/vcloud-rest/connection'
