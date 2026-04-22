import Foundation
import React
import UIKit
import AVFoundation

@objc(CardScannerModule)
final class CardScannerModule: NSObject, RCTBridgeModule {
  private var pendingResolve: RCTPromiseResolveBlock?
  private var pendingReject: RCTPromiseRejectBlock?

  static func requiresMainQueueSetup() -> Bool {
    true
  }

  @objc
  static func moduleName() -> String! {
    "CardScannerModule"
  }

  @objc(getCameraPermissionStatus:rejecter:)
  func getCameraPermissionStatus(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    resolve(Self.mapCameraStatus(status))
  }

  @objc(requestCameraPermission:rejecter:)
  func requestCameraPermission(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)

    if status == .notDetermined {
      AVCaptureDevice.requestAccess(for: .video) { granted in
        resolve(granted ? "authorized" : "denied")
      }
      return
    }

    resolve(Self.mapCameraStatus(status))
  }

  @objc(scanCard:rejecter:)
  func scanCard(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }

      if self.pendingResolve != nil || self.pendingReject != nil {
        reject("E_IN_PROGRESS", "Card scan already in progress", nil)
        return
      }

      guard let presenter = self.topViewController() else {
        reject("E_NO_VIEW_CONTROLLER", "Unable to find a view controller to present scanner", nil)
        return
      }

      self.pendingResolve = resolve
      self.pendingReject = reject

      let vc = CardScannerViewController()
      vc.modalPresentationStyle = .fullScreen

      vc.onCancel = { [weak self] in
        self?.rejectPending(code: "E_CANCELED", message: "Card scan canceled")
      }
      vc.onError = { [weak self] error in
        self?.rejectPending(code: "E_SCAN_FAILED", message: error.localizedDescription)
      }
      vc.onResult = { [weak self] result in
        self?.resolvePending(result: result)
      }

      presenter.present(vc, animated: true)
    }
  }

  private func resolvePending(result: CardScanResult) {
    let payload: [String: Any] = [
      "cardNumber": result.cardNumber,
      "cardNumberRedacted": result.cardNumberRedacted,
      "cardHolderName": result.cardHolderName,
      "expirationDate": result.expirationDate,
    ]
    pendingResolve?(payload)
    clearPending()
  }

  private func rejectPending(code: String, message: String) {
    pendingReject?(code, message, nil)
    clearPending()
  }

  private func clearPending() {
    pendingResolve = nil
    pendingReject = nil
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let keyWindow = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }
    var vc = keyWindow?.rootViewController

    while let presented = vc?.presentedViewController {
      vc = presented
    }
    if let nav = vc as? UINavigationController {
      vc = nav.visibleViewController
    }
    if let tab = vc as? UITabBarController {
      vc = tab.selectedViewController
    }
    return vc
  }

  private static func mapCameraStatus(_ status: AVAuthorizationStatus) -> String {
    switch status {
    case .authorized:
      return "authorized"
    case .denied:
      return "denied"
    case .restricted:
      return "restricted"
    case .notDetermined:
      return "notDetermined"
    @unknown default:
      return "unavailable"
    }
  }
}
