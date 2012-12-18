vcloud-rest
===========

DESCRIPTION
--
Unofficial ruby bindings for VMWare® vCloud Director's rest APIs v. 5.1.

See [vCloud API](http://pubs.vmware.com/vcd-51/topic/com.vmware.vcloud.api.doc_51/GUID-86CA32C2-3753-49B2-A471-1CE460109ADB.html) for details.

This code is ALPHA QUALITY.

INSTALLATION
--
This plugin is distributed as a Ruby Gem. To install it, run:

    gem install vcloud-rest

Depending on your system's configuration, you may need to run this command with root privileges.

vcloud-rest is tested against ruby 1.9.x and 1.8.7+.

FEATURES
--
- login/logout
- list/show organizations
- show VDCs
- list/show vApps
- create/start/stop/destroy vApps

TODO
--
- extend test coverage
- a lot more...

PREREQUISITES
--
- nokogiri ~> 1.5.5
- rest-client ~> 1.6.7

For testing purpose:
- minitest (included in ruby 1.9)
- minitest-spec (included in ruby 1.9)

USAGE
--
    require 'vcloud-rest/connection'
    conn = VCloudClient::Connection.new(HOST, USER, PASSWORD, ORG_NAME)
    conn.login
    conn.list_organizations

TESTING
--
Simply run:
    ruby spec/connection_spec.rb

Note: in order to run tests with ruby 1.8.7+ you need to export RUBYOPT="rubygems"

LICENSE
--

Author:: Stefano Tortarolo <stefano.tortarolo@gmail.com>

Copyright:: Copyright (c) 2012
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
