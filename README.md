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

## Usage

```js
import { scanPaymentCard } from 'react-native-card-detector';

const card = await scanPaymentCard();
```

## iOS permissions

Add `NSCameraUsageDescription` to your app `Info.plist`.

## Android permissions

This package declares `android.permission.CAMERA` in its library `AndroidManifest.xml`. Runtime permission is requested automatically when you call `scanPaymentCard()`.

## Permission behavior

By default `scanPaymentCard()` requests camera permission and, if not granted, shows a prompt to open Settings and throws an `E_CANCELED` error (so you can ignore it the same way you ignore user cancel).

You can customize the prompt:

```js
await scanPaymentCard({
  permission: {
    title: 'Camera Permission',
    message: 'Buddy Super would like to access your camera to scan a payment card.',
  }
});
```
