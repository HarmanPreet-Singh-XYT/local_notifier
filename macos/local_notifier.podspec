Pod::Spec.new do |s|
  s.name             = 'local_notifier'
  s.version          = '0.1.6'
  s.summary          = 'A Flutter plugin for displaying local notifications on macOS.'
  s.description      = <<-DESC
A Flutter plugin for displaying local notifications on macOS.
                       DESC
  s.homepage         = 'https://github.com/leanflutter/local_notifier'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'LiJianying' => 'lijy91@foxmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  
  s.platform = :osx, '10.14'
  s.osx.deployment_target = '10.14'
  s.frameworks = 'UserNotifications'
  
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end