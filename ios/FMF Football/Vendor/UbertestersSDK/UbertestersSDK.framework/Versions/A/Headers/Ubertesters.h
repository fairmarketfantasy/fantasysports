//
//  Ubertesters.h
//  UberTestLib
//
//  Created by Ubertesters on 9/7/13.
//  Copyright (c) 2013 Ubertesters. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "UTAlert.h"
//#import "NetworkClientUberTesters.h"
//#import "UserHelperUberTesters.h"

@class CustomViewUberTesters;
@class UserProfileViewController;
@class LockScreenViewControllerUberTesters;

typedef enum  {
    LockingModeDisableUbertestersIfBuildNotExist = 0,
    LockingModeLockAppIfBuildNotExist = 1
} LockingMode;

@interface Ubertesters : NSObject <UITextViewDelegate, UTAlertDelegate>
{
    BOOL dismissed;
    BOOL sendReport;
    UITextView *textView_feedback;
    UIView *feedbackView;
    UIButton *btn_send;
    NSString *_crashFilePath;
    
    BOOL isFirstTime;
    
    NSTimer *timerLogs;
}



@property (nonatomic, readonly) LockScreenViewControllerUberTesters *lockScreen;
@property (nonatomic, readonly) UserProfileViewController *userProfileScreen;
@property (nonatomic, retain) NSString* apiKey;
@property (nonatomic, retain) CustomViewUberTesters *mainView;

@property (nonatomic, assign) BOOL isOpenGL;
@property (nonatomic, assign) BOOL isInit;
@property (nonatomic, assign) BOOL isHide;
@property (nonatomic, assign) BOOL autoUpdate;
@property (nonatomic, assign) BOOL doNotShowLockScreen;


// if customer sends this property in dictionary properties as YES -> after app receive error code APPLICATION NO FOUND -> we will not close the app
@property (nonatomic, assign) LockingMode lockingMode; // DEFAULT 0

+ (Ubertesters*) shared;
- (void)initialize;
- (void)initialize:(LockingMode) mode;

//api
- (void)makeScreenshot;
- (void)showMenuPicker;
- (void)hideMenuPicker;
- (void)showMenu;
- (void)hideMenu;
- (void)UTLog:(NSString *)format level:(NSString *)level;

// public functions for lib's classes

- (BOOL)isOnline;
- (NSString *)checkForUpdate;
- (NSString *)getPhoneState;
- (void)postLogs:(NSString*)logs token:(NSString *)token;
- (void)postLog:(NSDictionary *)dictLog;
- (void)postCrash:(NSString*)log token:(NSString *)token state:(NSString *)state rid: (NSString *)rid uid: (NSString *)uid;
- (void)setAppStatus:(int) exitCode;
- (void)makeAppExit;
- (void)showUserProfileScreen;
- (void)showLockScreen;
- (void)showIpadSoomingSoonScreen;
- (void)makeUTLibWindowKeyAndVisible;
- (void)makeAppWindowKeyAndVisible;
- (UIWindow *)getUTLibWindow;
- (void)enableTimer:(BOOL)res;

- (void)registerLocalNotificationWithText:(NSString *)text forDate:(NSDate*)date;
- (void)playSystemSound:(int)soundID;
@end

// Handle Exception
void HandleUbertestersException(NSException *exception);
// calls when signal occures in the system
void SignalUbertestersHandler(int signal);
// install Urban HandleEception to the app and uber menu
void installUberErrorHandler(void);

