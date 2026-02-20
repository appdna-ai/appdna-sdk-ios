Pod::Spec.new do |s|
  s.name             = 'AppDNASDK'
  s.version          = '1.0.0'
  s.summary          = 'AppDNA iOS SDK — analytics, experiments, paywalls, onboarding, billing, push, and more.'
  s.description      = <<-DESC
Native iOS SDK for AppDNA providing analytics, remote configuration, feature flags,
experiments, paywalls, onboarding flows, surveys, web entitlements, and deferred deep links.
                       DESC
  s.homepage         = 'https://appdna.ai'
  s.license          = { :type => 'MIT' }
  s.author           = { 'AppDNA' => 'hello@appdna.ai' }
  s.source           = { :path => '.' }
  s.source_files     = 'Sources/AppDNASDK/**/*.swift'
  s.platform         = :ios, '15.0'
  s.swift_version    = '5.9'

  s.dependency 'KeychainAccess', '~> 4.2'
  s.dependency 'FirebaseFirestore', '~> 10.0'

  s.frameworks = 'UIKit', 'StoreKit', 'Foundation'
end
