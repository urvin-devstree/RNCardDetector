# react-native-card-detector

A user-friendly yet highly customizable tool that lets you capture card details using the device camera, eliminating the need to manually enter long card numbers and other information.

It opens a native scanner screen, reads the text from the card, and returns a clean, predictable result for your React Native code.

Behind the scenes:

- Android uses the [Lens24](https://central.sonatype.com/artifact/io.github.vlasentiy/lens24/overview) scanner UI.
- iOS uses [Apple Vision OCR](https://developer.apple.com/documentation/vision) to recognize text from the camera feed.

## Installation

```sh
npm i react-native-card-detector
cd ios && pod install && cd ..
```
> Requirements:
> - React Native `>= 0.60`
> - iOS deployment target `>= 15.1`
> - Android `minSdkVersion >= 21`

### `react-native-permissions` configuration

This library requests camera permission using `react-native-permissions`.

`react-native-permissions` is included as a dependency of this package, but you still need to do the native setup below (especially on iOS). If you already use `react-native-permissions` directly in your app, keep your existing setup.

How permission is handled:

- The library calls `request(PERMISSIONS.*.CAMERA)` before opening the scanner.
- If the user denies permission, it shows an alert and can take the user to device settings.

Please refer [react-native-permissions](https://www.npmjs.com/package/react-native-permissions) for installation and uses.

### Need to declare Camera Permission on Android and iOS native side

#### Android (`android/app/src/main/AndroidManifest.xml`)

This library declares camera permission in its own manifest and it should be merged into your app automatically. If your setup disables manifest merging or you want to be explicit, ensure your app has:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

#### iOS (`ios/<YourApp>/Info.plist`)

Apple requires a user-facing reason string for camera usage. Add:

```xml
<key>NSCameraUsageDescription</key>
<string>We need camera access to scan your payment card.</string>
```

## Uses

### Basic

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
      hint: 'Align your card inside the frame',
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

## Customisation

### `scanPaymentCard(options?)`

Pass an optional object to customize the permission dialog copy and/or the native scanner UI strings.

| Option | Default | Description |
|---|---|---|
| permission | { title: Camera Permission; description: This app would like to access your camera to scan a payment card. } | Text used for the alert shown when camera permission is denied.

### Scanner Text

#### Android & iOS
| Key | Default | Description |
|---|---|---|
| hint | Align your card inside the frame | Hint text shown on the scanner screen. |

#### Android

| Key | Default | Description |
|---|---|---|
| toolbarTitle | Scan card | Android Header title. |

#### iOS

| Key | Default | Description |
|---|---|---|
| hint | Align your card inside the frame | Hint text shown on the scanner screen. |
| statusLookingForCardNumber | Looking for card number… | Status while searching for card number. |
| statusReadingHoldSteady | Reading… hold steady (verifying number) | Status while reading/validating. |
| statusNumberFoundLookingForExpiry | Number found. Looking for expiry… | Status after number found. |
| cancel | Cancel | Cancel button label. |
| done | Done | Done button label. |
| torch | Torch | Torch button label. |

## Response
`scanPaymentCard()` resolves to:
```ts
type ScanPaymentCardResult = {
  cardNumber: string;
  cardHolderName: string;
  expirationDate: string;
};
```

## Conclusion

- `cardNumber`: only numbers (spaces/dashes removed) and validated, so it’s safer to use in your checkout flow.
- `cardHolderName`: best-effort name; some cards may not have a readable name, so it can be an empty string.
- `expirationDate`: best-effort parsing; if it can’t be confidently normalized, the raw value may be returned.