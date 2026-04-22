#import <React/RCTBridgeModule.h>

@interface RCT_EXTERN_MODULE(CardScannerModule, NSObject)

RCT_EXTERN_METHOD(scanCard:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)

@end

