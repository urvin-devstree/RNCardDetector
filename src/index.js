import {
  Alert,
  AppState,
  InteractionManager,
  Linking,
  NativeModules,
  PermissionsAndroid,
  Platform
} from 'react-native';

const { CardScannerModule } = NativeModules;

export const CAMERA_PERMISSION_STATUS = Object.freeze({
  AUTHORIZED: 'authorized',
  DENIED: 'denied',
  BLOCKED: 'blocked',
  RESTRICTED: 'restricted',
  NOT_DETERMINED: 'notDetermined',
  UNAVAILABLE: 'unavailable'
});

export const getCameraPermissionStatus = async () => {
  if (Platform.OS === 'android') {
    try {
      const granted = await PermissionsAndroid.check(PermissionsAndroid.PERMISSIONS.CAMERA);
      return granted ? CAMERA_PERMISSION_STATUS.AUTHORIZED : CAMERA_PERMISSION_STATUS.DENIED;
    } catch (e) {
      return CAMERA_PERMISSION_STATUS.UNAVAILABLE;
    }
  }

  if (!CardScannerModule?.getCameraPermissionStatus) {
    return CAMERA_PERMISSION_STATUS.UNAVAILABLE;
  }

  const status = await CardScannerModule.getCameraPermissionStatus();
  return status || CAMERA_PERMISSION_STATUS.UNAVAILABLE;
};

export const requestCameraPermission = async (options = {}) => {
  if (Platform.OS === 'android') {
    const rationale = options?.rationale || {
      title: 'Camera permission',
      message: 'Allow access to your camera to scan payment cards.',
      buttonPositive: 'Allow',
      buttonNegative: 'Not now'
    };

    try {
      const result = await PermissionsAndroid.request(
        PermissionsAndroid.PERMISSIONS.CAMERA,
        rationale
      );

      if (result === PermissionsAndroid.RESULTS.GRANTED) return CAMERA_PERMISSION_STATUS.AUTHORIZED;
      if (result === PermissionsAndroid.RESULTS.NEVER_ASK_AGAIN) return CAMERA_PERMISSION_STATUS.BLOCKED;
      return CAMERA_PERMISSION_STATUS.DENIED;
    } catch (e) {
      return CAMERA_PERMISSION_STATUS.UNAVAILABLE;
    }
  }

  if (!CardScannerModule?.requestCameraPermission) {
    return CAMERA_PERMISSION_STATUS.UNAVAILABLE;
  }

  const status = await CardScannerModule.requestCameraPermission();
  return status || CAMERA_PERMISSION_STATUS.UNAVAILABLE;
};

export const ensureCameraPermission = async (options = {}) => {
  const current = await getCameraPermissionStatus();
  if (current === CAMERA_PERMISSION_STATUS.AUTHORIZED) return CAMERA_PERMISSION_STATUS.AUTHORIZED;

  const next = await requestCameraPermission(options);
  if (next === CAMERA_PERMISSION_STATUS.AUTHORIZED) return CAMERA_PERMISSION_STATUS.AUTHORIZED;

  const promptToOpenSettings = options?.promptToOpenSettings === true;
  if (promptToOpenSettings) {
    const alertDelayMs = Number.isFinite(options?.alertDelayMs) ? options.alertDelayMs : 350;
    const title = options?.title || 'Camera Permission';
    const message =
      options?.message ||
      'This app would like to access your camera to scan a payment card.';
    const cancelText = options?.cancelText || 'Cancel';
    const okText = options?.okText || 'OK';
    const openSettingsOnOk = options?.openSettingsOnOk !== false;

    // OS permission dialogs can race with JS UI updates; wait for app to be active + interactions to finish.
    const showAlert = () => {
      Alert.alert(title, message, [
        { text: cancelText, style: 'cancel' },
        {
          text: okText,
          isPreferred: true,
          onPress: () => {
            if (!openSettingsOnOk) return;
            Linking.openSettings().catch(() => {});
          }
        }
      ]);
    };

    const scheduleShow = () => {
      let didShow = false;
      const tryShow = () => {
        if (didShow) return;
        didShow = true;
        showAlert();
      };

      // Fallback: InteractionManager callbacks can be starved by long-lived interactions in some apps.
      const fallbackDelayMs = Number.isFinite(options?.fallbackDelayMs)
        ? options.fallbackDelayMs
        : alertDelayMs;
      const timeoutId = setTimeout(tryShow, fallbackDelayMs);

      const waitForInteractions = options?.waitForInteractions !== false;
      if (!waitForInteractions) return;

      InteractionManager.runAfterInteractions(() => {
        clearTimeout(timeoutId);
        setTimeout(tryShow, alertDelayMs);
      });
    };

    if (AppState.currentState === 'active') {
      scheduleShow();
    } else {
      const sub = AppState.addEventListener('change', (state) => {
        if (state !== 'active') return;
        sub.remove();
        scheduleShow();
      });
    }
  }

  const err = new Error('Camera permission not granted');
  err.code = next === CAMERA_PERMISSION_STATUS.BLOCKED ? 'E_CAMERA_PERMISSION_BLOCKED' : 'E_CAMERA_PERMISSION';
  err.status = next;
  throw err;
};

const digitsOnly = (value) => String(value || '').replace(/\D+/g, '');

const redactPAN = (panDigits) => {
  const digits = digitsOnly(panDigits);
  if (digits.length < 4) return '';
  return `•••• •••• •••• ${digits.slice(-4)}`;
};

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

export const scanPaymentCard = async (options = {}) => {
  if (!CardScannerModule?.scanCard) {
    const err = new Error(`CardScannerModule.scanCard is not available on ${Platform.OS}`);
    err.code = 'E_MODULE_UNAVAILABLE';
    throw err;
  }

  const shouldRequestPermission = options?.requestPermission !== false;
  if (shouldRequestPermission) {
    const permissionOptions = {
      promptToOpenSettings: true,
      treatDeniedAsCancel: true,
      ...(options?.permission || {})
    };

    try {
      await ensureCameraPermission(permissionOptions);
    } catch (e) {
      const treatDeniedAsCancel = permissionOptions?.treatDeniedAsCancel !== false;
      if (
        treatDeniedAsCancel &&
        (e?.code === 'E_CAMERA_PERMISSION' || e?.code === 'E_CAMERA_PERMISSION_BLOCKED')
      ) {
        const err = new Error('Camera permission not granted');
        err.code = 'E_CANCELED';
        err.status = e?.status;
        throw err;
      }
      throw e;
    }
  }

  const result = await CardScannerModule.scanCard();

  const cardNumberRaw = String(result?.cardNumber || '');
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

  const expiry = normalizeExpiry(result?.expirationDate);
  const holderName = normalizeHolderName(result?.cardHolderName);
  const expirationDateRaw = String(result?.expirationDate || '');
  const expirationDate = expiry?.isValid ? String(expiry?.raw || '') : expirationDateRaw;
  const cardNumberRedactedRaw = String(result?.cardNumberRedacted || '');
  const cardNumberRedacted = cardNumberRedactedRaw || redactPAN(cardNumberDigits);

  return {
    cardNumber: cardNumberDigits,
    cardNumberRaw,
    cardNumberDigits,
    cardNumberRedacted,
    cardNumberRedactedRaw,
    cardHolderName: holderName,
    expirationDate,
    expirationDateRaw,
    expiryMonth: expiry?.month,
    expiryYear: expiry?.year,
    expiryFormatted: expiry?.raw,
    isCardNumberValidLuhn: true,
    isExpiryValid: expiry?.isValid,
    missing: {
      cardNumber: !cardNumberDigits,
      cardHolderName: !holderName,
      expiry: !expiry?.isValid
    },
    provider: Platform.OS === 'android' ? 'lens24' : 'vision-ocr'
  };
};
