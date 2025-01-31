#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#
Pod::Spec.new do |s|
  s.name             = 'video_player_extra'
  s.version          = '0.0.1'
  s.summary          = 'Flutter Video Player'
  s.description      = <<-DESC
A Flutter plugin for playing back video on a Widget surface.
Downloaded by pub (not CocoaPods).
                       DESC
  s.homepage         = 'https://github.com/Eittipat/plugins'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Flutter Dev Team' => 'flutter-dev@googlegroups.com' }
  s.source           = { :http => 'https://github.com/Eittipat/plugins/tree/master/packages/video_player_360/video_player' }
  s.documentation_url = 'https://pub.dev/packages/video_player'
  
  s.source_files = 'Classes/**/*', 'Classes/ext360/*.{h,m}'
  s.public_header_files = 'Classes/**/*.h', 'Classes/ext360/*.h'
  s.dependency 'Flutter'
  s.dependency 'GCDWebServer', '~> 3.0'
  s.dependency 'SDWebImage', '~> 5.0'
  
  s.platform = :ios, '9.0'
  s.pod_target_xcconfig = { 
    'DEFINES_MODULE' => 'YES',
    'VALID_ARCHS[sdk=iphonesimulator*]' => 'x86_64',
    'ENABLE_BITCODE' => 'NO'
  }
  
  # Explicitly include Metal framework
  s.frameworks = 'Metal', 'MetalKit'
  
  # Set minimum iOS version to 10.0 since Metal requires it
  s.platform = :ios, '10.0'
end

