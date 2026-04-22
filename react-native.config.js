module.exports = {
  dependency: {
    platforms: {
      android: {
        sourceDir: './android',
        packageImportPath: 'import com.reactnativecarddetector.CardScannerPackage;',
        packageInstance: 'new CardScannerPackage()'
      },
      ios: {
        podspecPath: './react-native-card-detector.podspec'
      }
    }
  }
};

