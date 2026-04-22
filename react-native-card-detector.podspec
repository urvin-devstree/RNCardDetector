Pod::Spec.new do |s|
  s.name         = 'react-native-card-detector'
  s.version      = '0.0.1'
  s.summary      = 'iOS payment card scanner native module for React Native'
  s.homepage     = 'https://github.com/urvin-devstree/RNCardDetector'
  s.license      = { :type => 'UNLICENSED' }
  s.author       = { 'urvin-devstree' => 'dev@buddy.invalid' }
  s.platform     = :ios, '15.1'
  s.source       = { :path => '.' }

  s.source_files = 'ios/Sources/**/*.{h,m,mm,swift}'
  s.swift_version = '5.0'

  s.dependency 'React-Core'
  s.frameworks = 'AVFoundation', 'Vision', 'UIKit', 'CoreMedia', 'CoreVideo'
end
