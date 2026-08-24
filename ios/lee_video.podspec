#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint lee_video.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'lee_video'
  s.version          = '0.1.0'
  s.summary          = 'Unified multi-kernel Flutter video player.'
  s.description      = <<-DESC
Unified multi-kernel Flutter video player for Android, iOS, macOS, and Windows.
                       DESC
  s.homepage         = 'https://github.com/LeelandoAi/Flutter_Video'
  s.license          = { :file => '../LICENSE' }
  s.author           = 'LeelandoAi'
  s.source           = { :path => '.' }
  s.source_files = 'lee_video/Sources/lee_video/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'

  # If your plugin requires a privacy manifest, for example if it uses any
  # required reason APIs, update the PrivacyInfo.xcprivacy file to describe your
  # plugin's privacy impact, and then uncomment this line. For more information,
  # see https://developer.apple.com/documentation/bundleresources/privacy_manifest_files
  # s.resource_bundles = {'lee_video_privacy' => ['lee_video/Sources/lee_video/PrivacyInfo.xcprivacy']}
end
