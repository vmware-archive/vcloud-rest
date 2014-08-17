vcloud-rest [![Build Status](https://secure.travis-ci.org/astratto/vcloud-rest.png?branch=master)](http://travis-ci.org/astratto/vcloud-rest) [![Dependency Status](https://gemnasium.com/astratto/vcloud-rest.png)](https://gemnasium.com/astratto/vcloud-rest)
===========

DESCRIPTION
--
Unofficial ruby bindings for VMware® vCloud Director's rest APIs.

Note: at this stage both _v.1.5_ and _v.5.1_ are supported. It defaults to _v.5.1_ but it's possible to specify *_api_version="1.5"*.

See [vCloud API](http://pubs.vmware.com/vcd-51/topic/com.vmware.vcloud.api.doc_51/GUID-86CA32C2-3753-49B2-A471-1CE460109ADB.html) for details.

INSTALLATION
--
This plugin is distributed as a Ruby Gem. To install it, run:

    gem install vcloud-rest

Depending on your system's configuration, you may need to run this command with root privileges.

vcloud-rest is tested against ruby 2.1.2, 2.0.0, 1.9.3 and ruby-head.

FEATURES
--
- login/logout
- list/show Organizations
- show VDCs
- show Catalogs
- show Catalog Items
- various vApp's commands
    - show
    - create/clone
    - start/stop/delete/reset/suspend/reboot
    - basic network configuration
- basic VM configuration
    - show
    - set cpu/RAM
    - basic network configuration
    - basic VM Guest Customization configuration
    - start/stop/delete/reset/suspend/reboot
- basic vApp compose capabilities
- basic vApp NAT port forwarding creation
- Catalog item upload with byterange upload and retry capabilities
- show Network details

TODO
--
- extend test coverage
- a lot more...

PREREQUISITES
--
- nokogiri
- rest-client
- httpclient
- ruby-progressbar

(see *vcloud_rest.gemspec* for details)

For testing purpose:
- minitest (included in ruby 1.9)
- webmock

USAGE
--

    require 'vcloud-rest/connection'
    conn = VCloudClient::Connection.new(HOST, USER, PASSWORD, ORG_NAME, VERSION)
    conn.login
    conn.get_organizations

EXAMPLE
--
A (mostly complete) example can be found in

    examples/example.rb

DEBUGGING
--
Debug can be enabled setting the following environment variables:

* *VCLOUD_REST_DEBUG_LEVEL*: to specify the log level (e.g., INFO, DEBUG)
* *VCLOUD_REST_LOG_FILE*: to specify the output file (defaults to STDOUT)

TESTING
--
Simply run:

    rake
Or:

    ruby spec/connection_spec.rb

Note: in order to run tests with ruby 1.8.x you need to export RUBYOPT="rubygems"

### Write new tests

Tests are now managed using VCR and thus real interactions are recorded and replayed.

In order to write new tests the following steps are required:

1. create a file *test_credentials.yml*
1. create a new test entry specifying a new VCR cassette *my_test_case.yml*
1. review and anonymize data if necessary under *spec/fixtures/vcr_cassettes/my_test_case.yml*

**Note:** values in *test_credentials.yml* are automatically anonymized.

Examples:

    => test_credentials.yml
    :host: https://vcloud_instance_url
    :username: test_username
    :password: test_password
    :org: test_organization


    => Test entry in connection_spec.rb
      it "should power off a given vapp" do
        VCR.use_cassette('vapps/poweroff_vapp') do
          connection.login
          task_id = connection.poweroff_vapp("65b4dbc9-b0b1-46e4-a420-8f8147369f8b")
          expect(task_id).to eq "ae791b59-4c9f-4fe2-9916-703f1fc3cbd5"
        end
      end

    => Recorded fixture (credentials auto-anonymized)
    ---
    http_interactions:
    - request:
        method: post
        uri: https://testuser%40testorg:testpass@testurl.local/api/sessions
        body:
          encoding: UTF-8
    ...


LICENSE
--

Author:: Stefano Tortarolo <stefano.tortarolo@gmail.com>

Copyright:: Copyright (c) 2012-2014
License:: Apache License, Version 2.0

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

CREDITS
--
This code was inspired by [knife-cloudstack](https://github.com/CloudStack-extras/knife-cloudstack).
