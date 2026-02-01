Pod::Spec.new do |s|
  s.name             = 'local_notifier'
  s.version          = '0.1.0'
  s.summary          = 'A new flutter plugin project.'
  s.description      = <<-DESC
A new flutter plugin project.
                       DESC
  s.homepage         = 'https://leanflutter.org'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'LiJianying' => 'lijy91@foxmail.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'FlutterMacOS'

  # macOS 10.14+ for UserNotifications framework
  s.platform = :osx, '10.14'
  
  # Add UserNotifications framework dependency
  s.frameworks = 'UserNotifications'
  
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end