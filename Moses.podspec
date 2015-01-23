Pod::Spec.new do |s|
  s.name                  =  "Moses"
  s.version               =  "0.0.1"
  s.summary               =  "An Swift OAuth2 client"
  s.homepage              =  "https://github.com/klaaspieter/Moses"
  s.license               =  "MIT"
  s.author                =  { "Klaas Pieter Annema" => "klaaspieter@annema.me" }
  s.social_media_url      =  "https://twitter.com/klaaspieter"
  s.source                =  { :git => "https://github.com/klaaspieter/Moses.git", :commit => "93a8716b9b3b4e6442303daf3d316dc9f56b0c9b" }
  s.ios.deployment_target =  "8.0"
  s.source_files          =  "Moses/*.swift"
  s.requires_arc          =  true
end
