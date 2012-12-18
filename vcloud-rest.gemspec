Gem::Specification.new do |s|
  s.name = %q{vcloud-rest}
  s.version = "0.0.1"
  s.date = %q{2012-12-14}
  s.authors = ["Stefano Tortarolo"]
  s.email = ['stefano.tortarolo@gmail.com']
  s.summary = %q{Unofficial ruby bindings for VMWare vCloud's API v.5.1}
  s.homepage = %q{http://www.vmware.com}
  s.description = %q{Ruby bindings to create, list and manage vCloud servers}

  s.add_dependency "nokogiri", "~> 1.5.5"
  s.add_dependency "rest-client", "~> 1.6.7"
  s.require_path = 'lib'
  s.files = ["CHANGELOG.md","README.md", "LICENSE"] + Dir.glob("lib/**/*")
end
