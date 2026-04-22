# react-native-card-detector

A user-friendly yet highly customizable tool that lets you capture card details using the device camera, eliminating the need to manually enter long card numbers and other information.

It opens a native scanner screen, reads the text from the card, and returns a clean, predictable result for your React Native code.

When scanning succeeds, you get:

- `cardNumber` (digits only; Luhn validated)
- `cardHolderName` (normalized + uppercased when possible)
- `expirationDate` (normalized when possible)

Behind the scenes:

- Android uses the Lens24 scanner UI.
- iOS uses Apple Vision OCR to recognize text from the camera feed.

## Installation

```sh
npm i react-native-card-detector
cd ios && pod install && cd ..
```
> Requirements:
> - React Native `>= 0.60`
> - iOS deployment target `>= 15.1`
> - Android `minSdkVersion >= 21`

## `react-native-permissions` configuration

This library requests camera permission using `react-native-permissions`.

`react-native-permissions` is included as a dependency of this package, but you still need to do the native setup below (especially on iOS). If you already use `react-native-permissions` directly in your app, keep your existing setup.

How permission is handled:

- The library calls `request(PERMISSIONS.*.CAMERA)` before opening the scanner.
- If the user denies permission, it shows an alert and can take the user to device settings.

Please refere [react-native-permissions](https://www.npmjs.com/package/react-native-permissions) for installation and uses.

## Need to declare Camera Permission on Android and iOS native side:

### Android (`android/app/src/main/AndroidManifest.xml`)

This library declares camera permission in its own manifest and it should be merged into your app automatically. If your setup disables manifest merging or you want to be explicit, ensure your app has:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### iOS (`ios/<YourApp>/Info.plist`)

Apple requires a user-facing reason string for camera usage. Add:

```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to scan your payment card.</string>
```

## Uses

### Basic

```js
import { scanPaymentCard } from 'react-native-card-detector';

const card = await scanPaymentCard();
```

### Recommended (with safe handling)

If permission is denied, `scanPaymentCard()` returns `undefined`. If scanning fails/cancels, it can throw.

```js
import { scanPaymentCard } from 'react-native-card-detector';

try {
  const card = await scanPaymentCard();
} catch (e) {
  console.log('Scan failed:', e?.code, e?.message);
}
```

### With permission-denied dialog customization

```js
const card = await scanPaymentCard({
  permission: {
    title: 'Camera Permission',
    description: 'We need camera access to scan your payment card.',
  },
});
```

### With scanner UI text customization

```js
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

## Customisation (Props passing) in description with uses

### `scanPaymentCard(options?)`

Pass an optional object to customize the permission dialog copy and/or the native scanner UI strings.

| Option | Type | Default | Description |
|---|---|---|---|
| `permission` | `{ title?: string; description?: string }` | `{ title: Camera Permission; description: This app would like to access your camera to scan a payment card. }` | Text used for the alert shown when camera permission is denied.

#### `Android : ScannerText`

| Key | Type | Default | Description |
|---|---|---|---|
| `hint` | `string` | `"Align the card in the frame"` | Hint text shown on the scanner screen. |
| `toolbarTitle` | `string` | `"Scan card"` | Android toolbar title. |

#### `iOS : ScannerText`

| Key | Type | Description |
|---|---|---|
| `hint` | `string` | Hint text shown on the scanner screen. |
| `statusLookingForCardNumber` | `string` | Status while searching for card number. |
| `statusReadingHoldSteady` | `string` | Status while reading/validating. |
| `statusNumberFoundLookingForExpiry` | `string` | Status after number found. |
| `cancel` | `string` | Cancel button label. |
| `done` | `string` | Done button label. |
| `torch` | `string` | Torch button label. |

## Response with description

`scanPaymentCard()` resolves to:

```ts
type ScanPaymentCardResult = {
  cardNumber: string;
  cardHolderName: string;
  expirationDate: string;
};
```

In simple terms:

- `cardNumber`: only numbers (spaces/dashes removed) and validated, so it’s safer to use in your checkout flow.
- `cardHolderName`: best-effort name; some cards may not have a readable name, so it can be an empty string.
- `expirationDate`: best-effort parsing; if it can’t be confidently normalized, the raw value may be returned.

### Error / cancel behaviour

- If camera permission is not granted, an alert is shown and the function returns `undefined`.
- If the native scanner is canceled, the promise rejects with code `E_CANCELED`.
- If no card number is detected, the promise rejects with code `E_NO_CARD_NUMBER`.
- If the card number fails Luhn validation, the promise rejects with code `E_INVALID_CARD_NUMBER`.
- Other native failures may reject with codes like `E_SCAN_FAILED`, `E_START_FAILED`, `E_NO_ACTIVITY`, or `E_IN_PROGRESS`.
