//
//  FFSplashViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFSessionViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "FFTextField.h"
#import "FFAlertView.h"
#import "UIView+FindFirstResponder.h"
#import <SBData/SBData.h>
#import "FFUser.h"
#import "FFSession.h"
#import "FFWebViewController.h"
#import "FFNavigationBarItemView.h"
#import <FacebookSDK/FacebookSDK.h>


@interface FFSessionViewController () <UIGestureRecognizerDelegate, UITextFieldDelegate, FFBalanceViewDataSource>
{
}

@property (nonatomic) UIView                *signInView;
@property (nonatomic) UIView                *signUpView;
@property (nonatomic) UITextField           *usernameSignupField;
@property (nonatomic) UITextField           *passwordSignupField;
@property (nonatomic) UITextField           *nameSignupField;
@property (nonatomic) UIButton              *signUpButton;
@property (nonatomic) UIButton              *signUpFacebookButton;
@property (nonatomic) UIButton              *signInButton;
@property (nonatomic) UIButton              *signInHeaderButton;
@property (nonatomic) UIButton              *signUpHeaderButton;
@property (nonatomic) UITextField           *usernameSigninField;
@property (nonatomic) UITextField           *passwordSigninField;
@property (nonatomic) UIGestureRecognizer   *dismissKeyboardRecognizer;
@property (nonatomic) CGFloat               keyboardHeight;
@property (nonatomic) BOOL                  keyboardIsShowing;
//@property (nonatomic) UIButton              *_balanceView;
@property (nonatomic) FFTickerMaximizedDrawerViewController *signInTicker, *signUpTicker;
@property (nonatomic) BOOL                  onSignUpView;

- (void)setupSignInView;
- (void)setupSignUpView;
- (void)signInHeaderSwitch:(id)sender;
- (void)signUpHeaderSwitch:(id)sender;
- (void)signIn:(id)sender;
- (void)signUp:(id)sender;
- (void)signUpFacebook:(id)sender;
- (void)forgotPassword:(id)sender;
- (void)dismissKeyboard:(id)sender;

@end

@implementation FFSessionViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        self.session = [FFSession lastUsedSessionWithUserClass:[FFUser class]];

    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        self.session = [FFSession lastUsedSessionWithUserClass:[FFUser class]];
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.navigationController.navigationBarHidden = YES;
//    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackOpaque];
}

- (id)ticker
{
    FFTickerMaximizedDrawerViewController *_maximizedTicker = [[FFTickerMaximizedDrawerViewController alloc] init];
    _maximizedTicker.view.backgroundColor = [FFStyle darkGreen];
    _maximizedTicker.session = self.session;
    [self.tickerDataSource addDelegate:_maximizedTicker];
    return _maximizedTicker;
}

- (void)viewDidAppear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gotLogout:)
                                                 name:SBLogoutNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gotLogout:)
                                                 name:SBLoginDidBecomeInvalidNotification
                                               object:nil];
    if (self.session != nil) {
//        [self.session syncUser];
        [self pollUser];
        [self.session syncPushToken];
        [self performSegueWithIdentifier:@"GoImmediatelyToHome" sender:nil];
        [self setNeedsStatusBarAppearanceUpdate];
    } else {
        [self.tickerDataSource refresh];
//        [self showControllerInDrawer:self.maximizedTicker
//             minimizedViewController:nil
//                              inView:self.signUpView
//                            animated:YES];
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
//    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)gotLogout:(NSNotification *)note
{
    NSLog(@"Got login/logout notification: %@", note);
    self.session = nil;
//    [self.navigationController popToRootViewControllerAnimated:YES];

    [self dismissViewControllerAnimated:YES completion:^{
        NSLog(@"done dismissing view controllers");
    }];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.signInView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, self.view.frame.size.height)];
    [self setupSignInView];
    
    self.signUpView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, self.view.frame.size.height)];
    [self setupSignUpView];
    
    [self.view addSubview:self.signInView];
    [self.view addSubview:self.signUpView];
    
    _dismissKeyboardRecognizer = [[UITapGestureRecognizer alloc]
                                  initWithTarget:self
                                  action:@selector(dismissKeyboard:)];
    _dismissKeyboardRecognizer.delegate = self;
    [self.view addGestureRecognizer:_dismissKeyboardRecognizer];
    
    _onSignUpView = YES;
}

- (void)setupSignUpView
{
    // background
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"loginbg.png"]];
    bg.contentMode = UIViewContentModeTop;
    bg.frame = self.signUpView.frame;
    [self.signUpView addSubview:bg];
    
    // header
    UIView *greenBg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 45)];
    greenBg.backgroundColor = [FFStyle darkGreen];
    [self.signUpView addSubview:greenBg];
    
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    [logo sizeToFit];
    logo.frame = CGRectCopyWithOrigin(logo.frame, CGPointMake(10, 15));
    [greenBg addSubview:logo];
    
    UIButton *signIn = [FFStyle clearButtonWithText:NSLocalizedString(@"Sign In", nil) borderColor:[FFStyle white]];
    signIn.frame = CGRectMake(self.signUpView.frame.size.width - 80, 7, 70, 30);
    [greenBg addSubview:signIn];
    [signIn addTarget:self action:@selector(signInHeaderSwitch:) forControlEvents:UIControlEventTouchUpInside];
    self.signInHeaderButton = signIn;
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        greenBg.frame = CGRectMake(0, 0, 320, 65);
        logo.frame = CGRectOffset(logo.frame, 0, 17);
        signIn.frame = CGRectOffset(signIn.frame, 0, 20);
    }
//
//    UIImageView *marketingCopy = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"dailyfantasyfootball.png"]];
//    marketingCopy.frame = CGRectMake(0, 44, 320, 60);
//    marketingCopy.contentMode = UIViewContentModeTop;
//    [self.signUpView addSubview:marketingCopy];
    
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, self.view.frame.size.height)];
    container.backgroundColor = [UIColor clearColor];
    [self.signUpView insertSubview:container belowSubview:greenBg];
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 90, 290, 60)];
    lab.font = [FFStyle lightFont:30];
    lab.text = NSLocalizedString(@"Sign Up", nil);
    lab.backgroundColor = [UIColor clearColor];
    lab.textColor = [FFStyle white];
    [container addSubview:lab];
    
    // text inputs
    UITextField *nam = [[FFTextField alloc] init];
    nam.layer.borderWidth = 1;
    nam.frame = CGRectMake(15, 151, 290, 44);
    nam.layer.borderColor = [FFStyle greyBorder].CGColor;
    nam.backgroundColor = [FFStyle white];
    nam.delegate = self;
    nam.placeholder = NSLocalizedString(@"name", nil);
    nam.returnKeyType = UIReturnKeyNext;
    nam.autocapitalizationType = UITextAutocapitalizationTypeNone;
    nam.autocorrectionType = UITextAutocorrectionTypeNo;
    nam.keyboardType = UIKeyboardTypeEmailAddress;
    //    un.text = //@"sam@mustw.in"; // TOOD: remove
    [container addSubview:nam];
    self.nameSignupField = nam;
    
    UITextField *un = [[FFTextField alloc] init];
    un.layer.borderWidth = 1;
    un.frame = CGRectMake(15, 205, 290, 44);
    un.layer.borderColor = [FFStyle greyBorder].CGColor;
    un.backgroundColor = [FFStyle white];
    un.delegate = self;
    un.placeholder = NSLocalizedString(@"email", nil);
    un.returnKeyType = UIReturnKeyNext;
    un.autocapitalizationType = UITextAutocapitalizationTypeNone;
    un.autocorrectionType = UITextAutocorrectionTypeNo;
    un.keyboardType = UIKeyboardTypeEmailAddress;
//    un.text = //@"sam@mustw.in"; // TOOD: remove
    [container addSubview:un];
    self.usernameSignupField = un;
    
    UITextField *pw = [[FFTextField alloc] init];
    pw.layer.borderWidth = 1;
    pw.layer.borderColor = [FFStyle greyBorder].CGColor;
    pw.backgroundColor = [FFStyle white];
    pw.delegate = self;
    pw.frame = CGRectMake(15, 260, 290, 44);
    pw.secureTextEntry = YES;
    pw.placeholder = NSLocalizedString(@"password", nil);
//    pw.text = @"omgnowai"; // TODO: remove
    pw.returnKeyType = UIReturnKeyGo;
    [container addSubview:pw];
    self.passwordSignupField = pw;
    
    // sign up buttons
    UIButton *signUp = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign Up", nil)
                                                color:[FFStyle brightGreen] borderColor:[FFStyle white]];
    signUp.frame = CGRectMake(15, 320, 290, 38);
    [signUp addTarget:self action:@selector(signUp:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:signUp];
    self.signUpButton = signUp;
    
    UIButton *fbSignUp = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign Up With Facebook", nil)
                                                  color:[FFStyle brightBlue] borderColor:[FFStyle white]];
    fbSignUp.frame = CGRectMake(15, 370, 290, 38);
    [fbSignUp addTarget:self action:@selector(signUpFacebook:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:fbSignUp];
    self.signUpFacebookButton = fbSignUp;
    
    if (IS_SMALL_DEVICE) {
        container.frame = CGRectOffset(container.frame, 0, -40);
        lab.font = [FFStyle lightFont:24];
        lab.frame = CGRectOffset(lab.frame, 0, 8);
    }
    
    _signUpTicker = [self ticker];
    _signUpTicker.view.frame = CGRectMake(0, CGRectGetMaxY(self.signUpView.frame)-95, 320, 95);
    [self.signUpView addSubview:_signUpTicker.view];
}

- (void)setupSignInView
{
    // background
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"loginbg.png"]];
    bg.contentMode = UIViewContentModeTop;
    bg.frame = self.signInView.frame;
    [self.signInView addSubview:bg];
    
    // header
    UIView *greenBg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 45)];
    greenBg.backgroundColor = [FFStyle darkGreen];
    [self.signInView addSubview:greenBg];
    
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    [logo sizeToFit];
    logo.frame = CGRectCopyWithOrigin(logo.frame, CGPointMake(10, 15));
    [greenBg addSubview:logo];
    
    UIButton *signup = [FFStyle clearButtonWithText:NSLocalizedString(@"Sign Up", nil) borderColor:[FFStyle white]];
    signup.frame = CGRectMake(self.signInView.frame.size.width - 80, 7, 70, 30);
    [greenBg addSubview:signup];
    [signup addTarget:self action:@selector(signUpHeaderSwitch:) forControlEvents:UIControlEventTouchUpInside];
    self.signUpHeaderButton = signup;
    
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        greenBg.frame = CGRectMake(0, 0, 320, 65);
        logo.frame = CGRectOffset(logo.frame, 0, 17);
        signup.frame = CGRectOffset(signup.frame, 0, 20);
    }
    
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, self.view.frame.size.height)];
    container.backgroundColor = [UIColor clearColor];
    [self.signInView insertSubview:container belowSubview:greenBg];
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 130, 290, 60)];
    lab.font = [FFStyle lightFont:30];
    lab.text = NSLocalizedString(@"Sign In", nil);
    lab.backgroundColor = [UIColor clearColor];
    lab.textColor = [FFStyle white];
    [container addSubview:lab];
    
    // text inputs
    UITextField *un = [[FFTextField alloc] init];
    un.layer.borderWidth = 1;
    un.frame = CGRectMake(15, 195, 290, 44);
    un.layer.borderColor = [FFStyle greyBorder].CGColor;
    un.backgroundColor = [FFStyle white];
    un.delegate = self;
    un.placeholder = NSLocalizedString(@"email", nil);
    un.returnKeyType = UIReturnKeyNext;
    un.autocapitalizationType = UITextAutocapitalizationTypeNone;
    un.autocorrectionType = UITextAutocorrectionTypeNo;
    un.keyboardType = UIKeyboardTypeEmailAddress;
//    un.text = @"sam@mustw.in"; // TODO: remove
    [container addSubview:un];
    self.usernameSigninField = un;
    
    UITextField *pw = [[FFTextField alloc] init];
    pw.layer.borderWidth = 1;
    pw.layer.borderColor = [FFStyle greyBorder].CGColor;
    pw.backgroundColor = [FFStyle white];
    pw.delegate = self;
    pw.frame = CGRectMake(15, 250, 290, 44);
    pw.secureTextEntry = YES;
    pw.placeholder = NSLocalizedString(@"password", nil);
    pw.returnKeyType = UIReturnKeyGo;
//    pw.text = @"omgnowai"; // TODO: remove
    [container addSubview:pw];
    self.passwordSigninField = pw;
    
    // sign in buttons
    UIButton *signIn = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign In", nil)
                                                color:[FFStyle brightGreen] borderColor:[FFStyle white]];
    signIn.frame = CGRectMake(15, 310, 290, 38);
    [signIn addTarget:self action:@selector(signIn:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:signIn];
    self.signInButton = signIn;
    
    UIButton *forgot = [UIButton buttonWithType:UIButtonTypeCustom];
    [forgot setTitle:NSLocalizedString(@"Forgot Your Password?", nil) forState:UIControlStateNormal];
    forgot.frame = CGRectMake(15, 355, 290, 50);
    forgot.titleLabel.font = [FFStyle lightFont:19];
    forgot.titleLabel.textAlignment = NSTextAlignmentCenter;
    [forgot setTitleColor:[FFStyle white] forState:UIControlStateNormal];
    [forgot setTitleColor:[FFStyle darkerColorForColor:[FFStyle white]] forState:UIControlStateHighlighted];
    [forgot addTarget:self action:@selector(forgotPassword:) forControlEvents:UIControlEventTouchUpInside];
    [container addSubview:forgot];
    
    if (IS_SMALL_DEVICE) {
        container.frame = CGRectOffset(container.frame, 0, -40);
        lab.font = [FFStyle lightFont:24];
        lab.frame = CGRectOffset(lab.frame, 0, 8);
    }
    
    _signInTicker = [self ticker];
    _signInTicker.view.frame = CGRectMake(0, CGRectGetMaxY(self.signInView.frame)-95, 320, 95);
    [self.signInView addSubview:_signInTicker.view];
}

// IBACTIONS -----------------------------------------------------------------------------------------------------------

- (void)signInHeaderSwitch:(id)sender
{
    _onSignUpView = NO;
    [UIView transitionFromView:self.signUpView
                        toView:self.signInView
                      duration:.35
                       options:UIViewAnimationOptionTransitionFlipFromRight
                    completion:^(BOOL finished) {
                        if (finished) {
                        }
                    }];
}

- (void)signUpHeaderSwitch:(id)sender
{
    _onSignUpView = YES;
    [UIView transitionFromView:self.signInView
                        toView:self.signUpView
                      duration:.35
                       options:UIViewAnimationOptionTransitionFlipFromRight
                    completion:^(BOOL finished) {
                        if (finished) {

                        }
                    }];
}

- (void)signIn:(id)sender
{
    // get/compile the regex we'll be using
    __strong static NSRegularExpression *regex = nil;
    if (regex == nil) {
        NSError *error = nil;
        NSString *emailRe = FF_EMAIL_REGEX;
        regex = [NSRegularExpression regularExpressionWithPattern:emailRe
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"Could not compile regex"
                                         userInfo:NSDictionaryOfVariableBindings(emailRe)];
        }
    }
    
    NSString *error = nil;
    
    if (!self.usernameSigninField.text.length) {
        error = NSLocalizedString(@"Please provide your email address", nil);
        goto validate_error;
    }
    {
        NSString *email = self.usernameSigninField.text;
        NSTextCheckingResult *result = [regex firstMatchInString:email options:0 range:NSMakeRange(0, email.length)];
        if (!result.range.length) {
            error = NSLocalizedString(@"Please provide a valid email address", nil);
            goto validate_error;
        }
    }
    if (!(self.passwordSigninField.text.length > 6)) {
        error = NSLocalizedString(@"Please provide a password at least 6 characters long", nil);
        goto validate_error;
    }
    
validate_error:
    if (error != nil) {
        FFAlertView *alert = [[FFAlertView alloc] initWithTitle:nil
                                                        message:error
                                              cancelButtonTitle:nil
                                                okayButtonTitle:NSLocalizedString(@"Okay", nil)
                                                       autoHide:YES];
        [alert showInView:self.view];
        return;
    }
    
    FFAlertView *progressAlert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Finding Account", @"creating account")
                                                           messsage:NSLocalizedString(@"In a few short moments you'll be on your way!",
                                                                                      @"on sign in, tells the user they will be signed in soon")
                                                       loadingStyle:FFAlertViewLoadingStylePlain];
    [progressAlert showInView:self.view];
    FFSession *sesh = [FFSession sessionWithEmailAddress:self.usernameSigninField.text userClass:[FFUser class]];
    [sesh loginWithEmail:self.usernameSigninField.text password:self.passwordSigninField.text success:^(id user) {
        [progressAlert hide];
        [[self.view findFirstResponder] resignFirstResponder];
        self.session = sesh;
        [self pollUser];
        [self.session syncPushToken];
        [FFSession setLastUsedSession:sesh];
        [self performSegueWithIdentifier:@"GotoHome" sender:nil];
        NSLog(@"successful login %@", user);
    } failure:^(NSError *err) {
        [progressAlert hide];
        [[[FFAlertView alloc] initWithError:err title:nil cancelButtonTitle:nil
                            okayButtonTitle:NSLocalizedString(@"Dismiss", @"dismiss error dialog")
                                   autoHide:YES]
         showInView:self.view];
    }];
}

- (void)forgotPassword:(id)sender
{
//    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:nil
//                                                   messsage:NSLocalizedString(@"Looking for your account...", nil)
//                                               loadingStyle:FFAlertViewLoadingStylePlain];
//    [alert showInView:self.view];
//    
//    double delayInSeconds = 2.0;
//    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
//    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
//        // TODO: actually do this...
//        [alert hide];
//        FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Check your email", nil)
//                                                        message:NSLocalizedString(@"We sent you an email with a link to reset your passord.", nil)
//                                              cancelButtonTitle:nil
//                                                okayButtonTitle:NSLocalizedString(@"Okay", nil)
//                                                       autoHide:YES];
//        [alert showInView:self.view];
//    });
    [self performSegueWithIdentifier:@"GotoForgotPassword" sender:nil];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"GotoForgotPassword"]) {
        FFWebViewController *vc = [segue.destinationViewController viewControllers][0];
        vc.URL = [NSURL URLWithString:@"http://google.com"];
    }
}

- (void)signUp:(id)sender
{
    // get/compile the regex we'll be using
    __strong static NSRegularExpression *regex = nil;
    if (regex == nil) {
        NSError *error = nil;
        NSString *emailRe = FF_EMAIL_REGEX;
        regex = [NSRegularExpression regularExpressionWithPattern:emailRe
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"Could not compile regex"
                                         userInfo:NSDictionaryOfVariableBindings(emailRe)];
        }
    }
    
    NSString *error = nil;
    
    if (!self.usernameSignupField.text.length) {
        error = NSLocalizedString(@"Please provide your email address", nil);
        goto validate_error;
    }
    if (!self.nameSignupField.text.length) {
        error = NSLocalizedString(@"Please provide a name", nil);
    }
    {
        NSString *email = self.usernameSignupField.text;
        NSTextCheckingResult *result = [regex firstMatchInString:email options:0 range:NSMakeRange(0, email.length)];
        if (!result.range.length) {
            error = NSLocalizedString(@"Please provide a valid email address", nil);
            goto validate_error;
        }
    }
    if (!(self.passwordSignupField.text.length > 6)) {
        error = NSLocalizedString(@"Please provide a password at least 6 characters long", nil);
        goto validate_error;
    }
    
validate_error:
    if (error != nil) {
        FFAlertView *alert = [[FFAlertView alloc] initWithTitle:nil
                                                        message:error
                                              cancelButtonTitle:nil
                                                okayButtonTitle:NSLocalizedString(@"Okay", nil)
                                                       autoHide:YES];
        [alert showInView:self.view];
        return;
    }
    
    FFAlertView *progressAlert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Creating Account", @"creating account")
                                                           messsage:NSLocalizedString(@"In a few short moments you'll be on your way!", nil)
                                                       loadingStyle:FFAlertViewLoadingStylePlain];
    [progressAlert showInView:self.view];
    
    FFSession *sesh = [FFSession sessionWithEmailAddress:self.usernameSignupField.text userClass:[FFUser class]];
    
    FFUser *user = [[FFUser alloc] initWithSession:sesh];
    user.email = self.usernameSignupField.text;
    user.name = self.nameSignupField.text;
    NSString *password = self.passwordSignupField.text;
    
    SBErrorBlock onErr = ^(NSError *err) {
        [progressAlert hide];
        [[[FFAlertView alloc] initWithError:err title:nil cancelButtonTitle:nil
                            okayButtonTitle:NSLocalizedString(@"Dismiss", @"dismiss error dialog")
                                   autoHide:YES]
         showInView:self.view];
    };
    
    SBSuccessBlock onSuccess = ^(id user) {
        [progressAlert hide];
        [[self.view findFirstResponder] resignFirstResponder];
        [FFSession setLastUsedSession:sesh];
        self.session = sesh;
        [self pollUser];
        [self.session syncPushToken];
        [self performSegueWithIdentifier:@"GotoHome" sender:nil];
    };
    
    [sesh registerAndLoginUser:user password:password success:onSuccess failure:onErr];
}

- (void)signUpFacebook:(id)sender
{
    [FBSession openActiveSessionWithReadPermissions:@[@"basic_info"] allowLoginUI:YES completionHandler:
     ^(FBSession *session, FBSessionState status, NSError *error) {
         [self fbSessionStateChanged:session state:status error:error];
     }];
}

- (void)fbSessionStateChanged:(FBSession *)session
                      state:(FBSessionState) state
                      error:(NSError *)error
{
    switch (state) {
        case FBSessionStateOpen:
            // pass the token back to the server
            [self loginFbToken:session.accessTokenData.accessToken];
            break;
        case FBSessionStateClosed:
        case FBSessionStateClosedLoginFailed:
            [FBSession.activeSession closeAndClearTokenInformation];
            break;
        default:
            break;
    }
    
    if (error) {
        UIAlertView *alertView = [[UIAlertView alloc]
                                  initWithTitle:@"Error"
                                  message:error.localizedDescription
                                  delegate:nil
                                  cancelButtonTitle:@"OK"
                                  otherButtonTitles:nil];
        [alertView show];
    }    
}

- (void)loginFbToken:(NSString *)accessToken
{
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Creating Account", nil)
                                                   messsage:nil loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    
    [FBRequestConnection startForMeWithCompletionHandler:^(FBRequestConnection *connection, id result, NSError *error) {
        if (error) {
            [alert hide];
            FFAlertView *ealert = [[FFAlertView alloc] initWithError:error title:nil cancelButtonTitle:nil
                                                     okayButtonTitle:NSLocalizedString(@"Dismiss", nil) autoHide:YES];
            [ealert showInView:self.view];
            return;
        }
        FFSession *sesh = [FFSession sessionWithEmailAddress:result[@"email"] userClass:[FFUser class]];
        [sesh registerAndLoginUsingFBAccessToken:accessToken fbUid:[result[@"id"] description] success:^(id successObj) {
            [alert hide];
            
            [[self.view findFirstResponder] resignFirstResponder];
            [FFSession setLastUsedSession:sesh];
            self.session = sesh;
            [self pollUser];
            [self.session syncPushToken];
            [self performSegueWithIdentifier:@"GotoHome" sender:nil];
        } failure:^(NSError *error) {
            FFAlertView *ealert = [[FFAlertView alloc] initWithError:error title:nil cancelButtonTitle:nil
                                                     okayButtonTitle:NSLocalizedString(@"Dismiss", nil) autoHide:YES];
            [ealert showInView:self.view];
        }];
    }];
}

// GESTURE RECOGNIZER --------------------------------------------------------------------------------------------------

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldReceiveTouch:(UITouch *)touch
{
//    NSLog(@"shouldReceiveTouch %@", touch);
    return YES;
}

- (void)dismissKeyboard:(id)sender
{
    [[self.view findFirstResponder] resignFirstResponder];
}

// TEXT FIELDS ---------------------------------------------------------------------------------------------------------

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
}

- (BOOL)textFieldShouldEndEditing:(UITextField *)textField
{
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField
{
    if (textField == self.usernameSigninField) {
        [self.passwordSigninField becomeFirstResponder];
        return NO;
    }
    if (textField == self.passwordSigninField) {
        [self signIn:nil];
    }
    if (textField == self.usernameSignupField) {
        [self.passwordSignupField becomeFirstResponder];
        return NO;
    }
    if (textField == self.passwordSignupField) {
        [self signUp:nil];
    }
    [textField endEditing:YES];
    return YES;
}

- (void)textFieldDidEndEditing:(UITextField *)textField
{
}

- (void)keyboardWillShow:(NSNotification *)note
{
    CGRect keyboardBounds;
    NSValue *aValue = [note.userInfo objectForKey:UIKeyboardFrameBeginUserInfoKey];
    
    [aValue getValue:&keyboardBounds];
    _keyboardHeight = keyboardBounds.size.height;
    if (!_keyboardIsShowing)
    {
        _keyboardIsShowing = YES;
        CGFloat offset = -100;
        if (IS_SMALL_DEVICE) {
            if (_onSignUpView) {
                offset = -65;
            } else {
                offset = -70;
            }
        }
        CGRect frame = CGRectOffset(self.view.frame, 0, offset);
        
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationDuration:0.3f];
        self.view.frame = frame;
        [UIView commitAnimations];
    }
}

- (void)keyboardWillHide:(NSNotification *)note
{
    CGRect keyboardBounds;
    NSValue *aValue = [note.userInfo valueForKey:UIKeyboardFrameEndUserInfoKey];
    [aValue getValue: &keyboardBounds];
    
    _keyboardHeight = keyboardBounds.size.height;
    if (_keyboardIsShowing)
    {
        _keyboardIsShowing = NO;
        CGFloat offset = 100;
        if (IS_SMALL_DEVICE) {
            if (_onSignUpView) {
                offset = 65;
            } else {
                offset = 70;
            }
        }
        CGRect frame = CGRectOffset(self.view.frame, 0, offset);
        
        [UIView beginAnimations:nil context:NULL];
        [UIView setAnimationBeginsFromCurrentState:YES];
        [UIView setAnimationDuration:0.3f];
        self.view.frame = frame;
        [UIView commitAnimations];
        
    }
}

// session controller stuff --------------------------------------------------------------------------------------------

- (UIView *)balanceView
{
//    if (!__balanceView) {
//        __balanceView = [UIButton buttonWithType:UIButtonTypeCustom]; //[[UIView alloc] initWithFrame:CGRectMake(0, 0, 105, 44)];
//        __balanceView.frame = CGRectMake(0, 0, 105, 44);
//        __balanceView.backgroundColor = [UIColor clearColor];
//        __balanceView.opaque = YES;
//        
//        UILabel *balance = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 100, 44)];
//        balance.backgroundColor = [UIColor clearColor];
//        balance.font = [FFStyle regularFont:12];
//        balance.textColor = [UIColor whiteColor];
//        balance.text = NSLocalizedString(@"Balance", nil);
//        balance.userInteractionEnabled = NO;
//        [__balanceView addSubview:balance];
//        
//        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(56, 10, 49, 24)];
//        background.backgroundColor = [FFStyle brightGreen];
//        background.layer.borderWidth = 1;
//        background.layer.borderColor = [FFStyle white].CGColor;
//        background.layer.cornerRadius = 4;
//        background.userInteractionEnabled = NO;
//        [__balanceView addSubview:background];
//        
//        UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 49, 24)];
//        value.backgroundColor = [UIColor clearColor];
//        value.font = [FFStyle boldFont:14];
//        value.textColor = [FFStyle white];
//        value.textAlignment = NSTextAlignmentCenter;
//        value.text = @"1000";
//        value.tag = 1337;
//        value.userInteractionEnabled = NO;
//        [background addSubview:value];
//    }
//    return __balanceView;
    FFBalanceButton *ret = [[FFBalanceButton alloc] initWithFrame:CGRectZero];
    ret.dataSource = self;
    return ret;
}

- (NSInteger)balanceViewGetBalance:(FFBalanceButton *)view
{
    FFUser *user = (FFUser *)self.session.user;
    return [user.tokenBalance integerValue];
}

- (void)pollUser
{
    [self.session syncUserSuccess:^(id successObj) {
        FFUser *user = successObj;
        
//        UILabel *lab = (UILabel *)[self.balanceView viewWithTag:1337];
//        lab.text = [NSString stringWithFormat:@"%d", [user.tokenBalance integerValue]];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:FFSessionDidUpdateUserNotification
                                                            object:nil
                                                          userInfo:@{FFUserKey: user}];
        
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self pollUser];
        });
    } failure:^(NSError *error) {
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self pollUser];
        });
    }];
}

@end


@implementation UIViewController (FFSessionController)

- (FFSessionViewController *)sessionController
{
    return [self lookForSessionController:self];
}

- (FFSessionViewController *)lookForSessionController:(UIViewController *)vc 
{
    if ([vc isKindOfClass:[FFSessionViewController class]]) {
        return (FFSessionViewController *)vc;
    }
    if (vc.parentViewController) {
        id ret = [self lookForSessionController:vc.parentViewController];
        if (ret) {
            return ret;
        }
    }
    if (vc.presentingViewController) {
        id ret = [self lookForSessionController:vc.presentingViewController];
        if (ret) {
            return ret;
        }
    }
    UINavigationController *navVc = nil;
    if (vc.navigationController) {
        navVc = vc.navigationController;
    } else if ([vc isKindOfClass:[UINavigationController class]]) {
        navVc = (UINavigationController *)vc;
    }
    if (navVc) {
        for (UIViewController *nvc in navVc.viewControllers) {
            id ret = [self lookForSessionController:nvc];
            if (ret) {
                return ret;
            }
        }
    }
    return nil;
}

- (SBSession *)session
{
    return self.sessionController.session;
}

@end
