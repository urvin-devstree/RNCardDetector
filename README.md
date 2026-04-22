# react-native-card-detector

Native payment card scanning for React Native:

- Android: Lens24 SDK
- iOS: Apple Vision OCR (camera + text recognition)

## Install (GitHub)

```json
"react-native-card-detector": "github:urvin-devstree/RNCardDetector"
```

This package uses `react-native-permissions` for camera permission. If your app doesn’t already have it, install it too:
[react-native-permissions](https://www.npmjs.com/package/react-native-permissions)

## Usage

```js
import { scanPaymentCard } from 'react-native-card-detector';

const card = await scanPaymentCard();

Or customize the permission denied dialog:
const card = await scanPaymentCard({
  permission: {
    title: 'Camera Permission',
    description: 'We need camera access to scan your payment card.'
  }
});

Or customize the scanner UI text (optional):
const card = await scanPaymentCard({
  scannerText: {
    android: {
      hint: 'Align the card in the frame',
      toolbarTitle: 'Scan card',
    },
    ios: {
      hint: 'Align your card inside the frame',
      statusLookingForCardNumber: 'Looking for card number…',
      statusReadingHoldSteady: 'Reading… hold steady (verifying number)',
      statusNumberFoundLookingForExpiry: 'Number found. Looking for expiry…',
      cancel: 'Cancel',
      done: 'Done',
      torch: 'Torch',
    },
  },
});
```

## Response
```js
let cardNumber: card?.cardNumber,
let cardHolderName: card?.cardHolderName,
let expiryDate: card?.expirationDate
```