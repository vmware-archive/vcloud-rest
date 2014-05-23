# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'vcloud-rest/version'

Gem::Specification.new do |s|
  s.name = %q{vcloud-rest}
  s.version = VCloudClient::VERSION
  s.authors = ["Stefano Tortarolo"]
  s.email = ['stefano.tortarolo@gmail.com']
  s.summary = %q{Unofficial ruby bindings for VMWare vCloud's API}
  s.homepage = %q{https://github.com/astratto/vcloud-rest}
  s.description = %q{Ruby bindings to create, list and manage vCloud servers}
  s.license     = 'Apache 2.0'

  s.add_dependency "nokogiri", ">= 1.5.10"
  s.add_dependency "rest-client", '~> 1.6', '>= 1.6.7'
  s.add_dependency "httpclient", '~> 2.3', '>= 2.3.3'
  s.add_dependency "ruby-progressbar", "~> 1.5", ">= 1.5.1"

  s.add_development_dependency "rake", '~> 10.1'
  s.add_development_dependency "rspec", '~> 2.14'
  s.add_development_dependency "webmock", '~> 1.13'
  s.add_development_dependency "vcr", '~> 2.9'
  s.add_development_dependency "simplecov", '~> 0.8', '>= 0.8.2'
  s.add_development_dependency "coveralls"

  s.require_path = 'lib'
  s.files = ["CHANGELOG.md","README.md", "LICENSE"] + Dir.glob("lib/**/*")
end
