Pod::Spec.new do |s|
  s.name             = 'realtime_audio'
  s.version          = '0.0.1'
  s.summary          = 'Audio package to handle streaming chunk playback & recording to use with realtime APIs like OpenAI Realtime, HumeAI Voice and others.'
  s.description      = <<-DESC
  Realtime audio plugin for Flutter.
                       DESC
  s.homepage         = 'https://github.com/volskaya/realtime_audio.flutter'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Roland' => 'roland@volskaya.dev' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*.{swift,h,m,mm}'
  s.public_header_files = 'Classes/apm/WebRtcApmBridge.h'
  s.vendored_libraries = 'Libs/libwebrtc_apm_wrapper.a'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++14',
    'HEADER_SEARCH_PATHS' => '"$(PODS_TARGET_SRCROOT)/Libs/include"',
    'OTHER_LDFLAGS' => '-lc++',
  }
  s.swift_version = '5.0'
  s.library = 'c++'
end
