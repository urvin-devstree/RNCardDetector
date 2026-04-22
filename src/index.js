import { NativeModules, Alert, Linking, Platform } from 'react-native';
import { PERMISSIONS, request } from 'react-native-permissions';

const { CardScannerModule } = NativeModules;

const isAndroid = Platform.OS == 'android';

const digitsOnly = (value) => String(value || '').replace(/\D+/g, '');

const luhnCheck = (pan) => {
  const value = digitsOnly(pan);
  if (value.length < 12) return false;
  let sum = 0;
  let shouldDouble = false;
  for (let i = value.length - 1; i >= 0; i--) {
    let digit = Number(value[i]);
    if (Number.isNaN(digit)) return false;
    if (shouldDouble) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    shouldDouble = !shouldDouble;
  }
  return sum % 10 == 0;
};

const normalizeExpiry = (expirationDate) => {
  const raw = String(expirationDate || '').trim();
  const match = raw.match(/^(\d{1,2})\s*[/\-]\s*(\d{2,4})$/);
  let month = null;
  let year = null;
  if (match) {
    month = Number(match[1]);
    year = Number(match[2]);
  } else {
    const digits = raw?.replace(/\D+/g, '');
    if (digits?.length == 4) {
      month = Number(digits?.slice(0, 2));
      year = Number(digits?.slice(2, 4));
    } else if (digits?.length === 6) {
      month = Number(digits?.slice(0, 2));
      year = Number(digits?.slice(2, 6));
    }
  }
  if (month == null || year == null) return { raw, month: null, year: null, isValid: false };
  if (!Number.isFinite(month) || month < 1 || month > 12) return { raw, month: null, year: null, isValid: false };
  if (year < 100) year += 2000;
  if (!Number.isFinite(year) || year < 2000 || year > 2100) return { raw, month, year: null, isValid: false };
  return { raw: `${String(month).padStart(2, '0')}/${String(year).slice(-2)}`, month, year, isValid: true };
};

const normalizeHolderName = (name) => {
  if (/\d/.test(String(name || ''))) return '';
  const raw = String(name || '')
    ?.replace(/[^A-Za-z\s.'-]+/g, ' ')
    ?.replace(/\s+/g, ' ')
    ?.trim();
  if (!raw) return '';
  return raw?.toUpperCase();
};

const handleCameraPermissionDenied = (permission) => {
  Alert.alert(
    (permission?.title || `Camera Permission`),
    (permission?.description || `This app would like to access your camera to scan a payment card.`),
    [{ text: 'Cancel', style: 'cancel' },
    { text: 'OK', onPress: handleOpenDeviceSettings, isPreferred: true }]
  );
};

const handleOpenDeviceSettings = () => {
  Linking.openSettings();
};

export const scanPaymentCard = async ({ permission, scannerText } = {}) => {
  const status = await request(isAndroid ? PERMISSIONS.ANDROID.CAMERA : PERMISSIONS.IOS.CAMERA);
  if (status != 'granted') {
    handleCameraPermissionDenied(permission);
    return;
  };

  const scan = async () => CardScannerModule.scanCard();
  const scanWithOptions = async (options) => {
    if (!options) return scan();
    if (typeof CardScannerModule?.scanCardWithOptions === 'function') {
      return CardScannerModule.scanCardWithOptions(options);
    }
    return scan();
  };

  let response = await scanWithOptions(scannerText);
  const cardNumberRaw = String(response?.cardNumber || '');
  const cardNumberDigits = digitsOnly(cardNumberRaw);
  if (!cardNumberDigits) {
    const err = new Error('No card number detected. Please try again.');
    err.code = 'E_NO_CARD_NUMBER';
    throw err;
  }
  if (!luhnCheck(cardNumberDigits)) {
    const err = new Error('Invalid card number detected. Please try again.');
    err.code = 'E_INVALID_CARD_NUMBER';
    throw err;
  }

  const expiry = normalizeExpiry(response?.expirationDate);
  const holderName = normalizeHolderName(response?.cardHolderName);
  const expirationDateRaw = String(response?.expirationDate || '');
  const expirationDate = expiry?.isValid ? String(expiry?.raw || '') : expirationDateRaw;

  return {
    cardNumber: cardNumberDigits,
    cardHolderName: holderName,
    expirationDate
  };
};
