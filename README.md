# react-native-card-detector

Native payment card scanning for React Native:

- Android: Lens24 SDK
- iOS: Apple Vision OCR (camera + text recognition)

## Install (GitHub)

```json
{
  "react-native-card-detector": "github:urvin-devstree/RNCardDetector"
}
```

This package uses `react-native-permissions` for camera permission. If your app doesn’t already have it, install it too:

```sh
npm i react-native-permissions
```

## Usage

```js
import { scanPaymentCard } from 'react-native-card-detector';

const card = await scanPaymentCard();
// or customize the permission denied dialog:
// const card = await scanPaymentCard({
//   permission: {
//     title: 'Camera Permission',
//     description: 'We need camera access to scan your payment card.'
//   }
// });
```

## Permissions (react-native-permissions)

This library requests the camera permission using `react-native-permissions`.

### iOS

1) Add `NSCameraUsageDescription` to your app `Info.plist`.

2) Enable the Camera permission handler in your app `ios/Podfile`:

```rb
def node_require(script)
  # Resolve script with node to allow for hoisting
  require Pod::Executable.execute_command(
    'node',
    ['-p', "require.resolve('#{script}', {paths: [process.argv[1]]})", __dir__]
  ).strip
end

node_require('react-native-permissions/scripts/setup.rb')

setup_permissions([
  'Camera'
])
```

Then run `npx pod-install` (or `cd ios && pod install`).

### Android

Add the camera permission to your app `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

The permission is requested at runtime via `react-native-permissions`.
