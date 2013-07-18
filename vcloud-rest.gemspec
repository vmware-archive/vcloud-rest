Gem::Specification.new do |s|
  s.name = %q{vcloud-rest}
  s.version = "0.2.2"
  s.date = %q{2013-05-13}
  s.authors = ["Stefano Tortarolo"]
  s.email = ['stefano.tortarolo@gmail.com']
  s.summary = %q{Unofficial ruby bindings for VMWare vCloud's API}
  s.homepage = %q{https://github.com/astratto/vcloud-rest}
  s.description = %q{Ruby bindings to create, list and manage vCloud servers}
  s.license     = 'Apache 2.0'

  s.add_dependency "nokogiri", "~> 1.6.0"
  s.add_dependency "rest-client", "~> 1.6.7"
  s.require_path = 'lib'
  s.files = ["CHANGELOG.md","README.md", "LICENSE"] + Dir.glob("lib/**/*")
end
