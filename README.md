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

