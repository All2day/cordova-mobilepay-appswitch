#import "CordovaMobilePayAppSwitch.h"

#import <Cordova/CDVAvailability.h>
#import "MobilePayManager.h"

@implementation CordovaMobilePayAppSwitch

NSString *myCallbackId;

- (void)pluginInitialize {
  NSLog(@"plugin initializing");
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(finishLaunching:) name:UIApplicationDidFinishLaunchingNotification object:nil];
}
- (void)finishLaunching:(NSNotification *)notification
{
    // Put here the code that should be on the AppDelegate.m
    // NSString* urlScheme = [self.commandDelegate.settings objectForKey:[@"urlScheme" lowercaseString]];
    // NSLog(@"finshLaunching %@", urlScheme);
    NSLog(@"Finish launching mobile pay plugin");
}
- (void)startPayment:(CDVInvokedUrlCommand *)command {
    NSString* urlScheme = [self.commandDelegate.settings objectForKey:[@"urlScheme" lowercaseString]];
    NSString* merchantId = [self.commandDelegate.settings objectForKey:[@"merchantId" lowercaseString]];
    NSString* callbackUrl = [self.commandDelegate.settings objectForKey:[@"callbackUrl" lowercaseString]];

    //Used for showing errors
    NSDictionary *jsonResultDict = nil;
    CDVPluginResult *result = nil;

    //If MobilePay is not installed
    if (![[MobilePayManager sharedInstance]isMobilePayInstalled:MobilePayCountry_Denmark]) {
      //Another method:
      UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"MobilePay påkrævet"
                                                                       message:@"For at kunne betale er det nødvendigt at have MobilePay installeret"
                                                                preferredStyle:UIAlertControllerStyleAlert];
      //We add buttons to the alert controller by creating UIAlertActions:
      UIAlertAction *actionCancel = [UIAlertAction actionWithTitle:@"Fortryd"
                                                       style:UIAlertActionStyleDefault
                                                     handler:nil]; //You can use a block here to handle a press on this button

      UIAlertAction *actionInstall = [UIAlertAction actionWithTitle:@"Installer"
                                              style:UIAlertActionStyleDefault
                                              handler:^(UIAlertAction *action) {
                                                NSURL *url = [NSURL URLWithString:[[MobilePayManager sharedInstance] mobilePayAppStoreLinkDK]];
                                                [[UIApplication sharedApplication] openURL:url];
                                              }]; //You can use a block here to handle a press on this button


      [alertController addAction:actionCancel];
      [alertController addAction:actionInstall];

      UIViewController* rootController = [UIApplication sharedApplication].delegate.window.rootViewController;

      [rootController presentViewController:alertController animated:YES completion:nil];
      return;
    }

    NSLog(@"startPayment, urlScheme: '%@', merchantId: '%@''", urlScheme, merchantId);
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleOpenURL:) name:urlScheme object:nil];
    //NSLog(@"After addObserver: country:'%i'",MobilePayCountry_Denmark);
    [[MobilePayManager sharedInstance] setupWithMerchantId:merchantId merchantUrlScheme:urlScheme country:MobilePayCountry_Denmark];
    //NSLog(@"After setupWithMerchantId");
    //NSLog(@"command:'%@'",command);
    //setting callback url
    [[MobilePayManager sharedInstance] setServerCallbackUrl:callbackUrl];

    //Setting the capture type
    [MobilePayManager sharedInstance].captureType = MobilePayCaptureType_Reserve ;
    myCallbackId = command.callbackId;

    NSString* amountStr = [command.arguments objectAtIndex:0];

    //fetch the order id according to its type, as the json mechanism behind the scenes can choose NSNumer instead of NSString
    NSString* orderId = nil;
    if([[command.arguments objectAtIndex:1] isKindOfClass:[NSNumber class]]){
      orderId = [[command.arguments objectAtIndex:1] stringValue];
    }
    else if([[command.arguments objectAtIndex:1] isKindOfClass:[NSString class]]){
      orderId = [command.arguments objectAtIndex:1];
    } else {
      jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
      @"orderId not string or number", @"errorMessage",
      nil];
      result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:jsonResultDict];
      [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];
      return;
    }


    float fAmount = [amountStr floatValue];

    MobilePayPayment *payment = nil;
    @try{
      payment = [[MobilePayPayment alloc]initWithOrderId:orderId productPrice:fAmount];
    }
    @catch (NSException *exception){
      jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
      @"Error when creating payment", @"errorMessage",
      nil];
      result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:jsonResultDict];
      [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];
      return;
    }

        //No need to start a payment if one or more parameters are missing
        if (payment && orderId /*&& ([orderId length] > 0)*/ && (fAmount >= 0)) {
            @try{

              [[MobilePayManager sharedInstance]beginMobilePaymentWithPayment:payment error:^(NSError * _Nonnull error) {
                  NSLog(@"error in payment");

                  NSDictionary *jsonResultDict = nil;
                  CDVPluginResult *result = nil;

                  jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
                  @"Error in beginMobilePaymentWithPayment", @"errorMessage",
                  nil];
                  result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:jsonResultDict];
                  [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];


              }];
            }
            @catch (NSException *exception){
              jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
              @"Exception in beginMobilePaymentWithPayment", @"errorMessage",
              nil];
              result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:jsonResultDict];
              [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];
              return;
            }
        } else {

          jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
          @"price and orderId not ok", @"errorMessage",
          nil];
          result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:jsonResultDict];
          [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];
          return;
        }
}
- (void)handleOpenURL:(NSNotification*)notification
{
    NSURL* url = [notification object];
    NSLog(@"handleOpenUrl called");
    if ([url isKindOfClass:[NSURL class]]) {
        [self handleMobilePayPaymentWithUrl:url];
        NSLog(@"handleOpenURL %@", url);
    }
}

- (void)handleMobilePayPaymentWithUrl:(NSURL *)url
{
    [[MobilePayManager sharedInstance]handleMobilePayPaymentWithUrl:url success:^(MobilePaySuccessfulPayment * _Nullable mobilePaySuccessfulPayment) {
        NSString *orderId = mobilePaySuccessfulPayment.orderId;
        NSString *transactionId = mobilePaySuccessfulPayment.transactionId;
        NSString *amountWithdrawnFromCard = [NSString stringWithFormat:@"%f",mobilePaySuccessfulPayment.amountWithdrawnFromCard];


        NSDictionary *jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
        orderId, @"orderId",
        transactionId, @"transactionId",
        amountWithdrawnFromCard, @"amountWithdrawnFromCard",
        nil];

        NSData *jsonResultData = [NSJSONSerialization dataWithJSONObject:jsonResultDict options:NSJSONWritingPrettyPrinted error: nil];
        NSString *jsonResultString = [[NSString alloc] initWithData:jsonResultData encoding:NSUTF8StringEncoding];
        NSLog(@"SuccessResult:\n%@", jsonResultString);

        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsDictionary:jsonResultDict];
        [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];

    } error:^(NSError * _Nonnull error) {
        NSDictionary *dict = error.userInfo;
        NSString *errorMessage = [dict valueForKey:NSLocalizedFailureReasonErrorKey];

        NSDictionary *jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInteger:error.code], @"errorCode",
        errorMessage, @"errorMessage",
        nil];

        NSData *jsonResultData = [NSJSONSerialization dataWithJSONObject:jsonResultDict options:NSJSONWritingPrettyPrinted error: nil];
        NSString *jsonResultString = [[NSString alloc] initWithData:jsonResultData encoding:NSUTF8StringEncoding];
        NSLog(@"ErrorResult:\n%@", jsonResultString);

        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:jsonResultDict];
        [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];

        //TODO: show an appropriate error message to the user. Check MobilePayManager.h for a complete description of the error codes

        //An example of using the MobilePayErrorCode enum
        //if (error.code == MobilePayErrorCodeUpdateApp) {
        //    NSLog(@"You must update your MobilePay app");
        //}
    } cancel:^(MobilePayCancelledPayment * _Nullable mobilePayCancelledPayment) {

        NSDictionary *jsonResultDict = [NSDictionary dictionaryWithObjectsAndKeys:
        @"Cancelled", @"errorMessage",
        mobilePayCancelledPayment.orderId, @"orderId",
        nil];

        NSData *jsonResultData = [NSJSONSerialization dataWithJSONObject:jsonResultDict options:NSJSONWritingPrettyPrinted error: nil];
        NSString *jsonResultString = [[NSString alloc] initWithData:jsonResultData encoding:NSUTF8StringEncoding];
        NSLog(@"CancelledResult:\n%@", jsonResultString);

        CDVPluginResult *result = [CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:jsonResultDict];
        [self.commandDelegate sendPluginResult:result callbackId:myCallbackId];

    }];
}

@end
