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

@interface FFSessionViewController () <UIGestureRecognizerDelegate, UITextFieldDelegate>
{
}

@property (nonatomic) UIView                *signInView;
@property (nonatomic) UIView                *signUpView;
@property (nonatomic) UITextField           *usernameSignupField;
@property (nonatomic) UITextField           *passwordSignupField;
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
@property (nonatomic) UIView                *_balanceView;

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
        // Custom initialization
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    self.navigationController.navigationBarHidden = YES;
    [[UIApplication sharedApplication] setStatusBarStyle:UIStatusBarStyleBlackTranslucent];
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
    SBSession *lastSession = [SBSession lastUsedSessionWithUserClass:[FFUser class]];
    if (lastSession != nil) {
        [lastSession syncUser];
        [self performSegueWithIdentifier:@"GoImmediatelyToHome" sender:nil];
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)awakeFromNib
{
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gotLogout:)
                                                 name:SBLogoutNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(gotLogout:)
                                                 name:SBLoginDidBecomeInvalidNotification
                                               object:nil];
}

- (void)gotLogout:(NSNotification *)note
{
    NSLog(@"Got login/logout notification: %@", note);
    [self.navigationController popToRootViewControllerAnimated:YES];

    [self dismissViewControllerAnimated:YES completion:^{
        NSLog(@"done dismissing view controllers");
    }];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.signInView = [[UIView alloc] initWithFrame:CGRectOffset(self.view.frame, 0, -20)];
    [self setupSignInView];
    
    self.signUpView = [[UIView alloc] initWithFrame:CGRectOffset(self.view.frame, 0, -20)];
    [self setupSignUpView];
    
    [self.view addSubview:self.signInView];
    [self.view addSubview:self.signUpView];
    
     _dismissKeyboardRecognizer = [[UITapGestureRecognizer alloc]
                                   initWithTarget:self
                                   action:@selector(dismissKeyboard:)];
    _dismissKeyboardRecognizer.delegate = self;
    [self.view addGestureRecognizer:_dismissKeyboardRecognizer];
}

- (void)setupSignUpView
{
    // background
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-splash-bg.png"]];
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
    
    UIImageView *marketingCopy = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-splash-copy.png"]];
    [marketingCopy sizeToFit];
    marketingCopy.center = CGPointMake(160, 130);
    [self.signUpView addSubview:marketingCopy];
    
    // text inputs
    UITextField *un = [[FFTextField alloc] init];
    un.layer.borderWidth = 1;
    un.frame = CGRectMake(15, 225, 290, 44);
    un.layer.borderColor = [FFStyle greyBorder].CGColor;
    un.backgroundColor = [FFStyle white];
    un.delegate = self;
    un.placeholder = NSLocalizedString(@"email", nil);
    un.returnKeyType = UIReturnKeyNext;
    un.autocapitalizationType = UITextAutocapitalizationTypeNone;
    un.autocorrectionType = UITextAutocorrectionTypeNo;
    un.keyboardType = UIKeyboardTypeEmailAddress;
    un.text = @"sam@mustw.in"; // TOOD: remove
    [self.signUpView addSubview:un];
    self.usernameSignupField = un;
    
    UITextField *pw = [[FFTextField alloc] init];
    pw.layer.borderWidth = 1;
    pw.layer.borderColor = [FFStyle greyBorder].CGColor;
    pw.backgroundColor = [FFStyle white];
    pw.delegate = self;
    pw.frame = CGRectMake(15, 280, 290, 44);
    pw.secureTextEntry = YES;
    pw.placeholder = NSLocalizedString(@"password", nil);
    pw.text = @"omgnowai"; // TODO: remove
    pw.returnKeyType = UIReturnKeyGo;
    [self.signUpView addSubview:pw];
    self.passwordSignupField = pw;
    
    // sign up buttons
    UIButton *signUp = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign Up", nil)
                                                color:[FFStyle brightGreen] borderColor:[FFStyle white]];
    signUp.frame = CGRectMake(15, 340, 290, 38);
    [signUp addTarget:self action:@selector(signUp:) forControlEvents:UIControlEventTouchUpInside];
    [self.signUpView addSubview:signUp];
    self.signUpButton = signUp;
    
    UIButton *fbSignUp = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign Up With Facebook", nil)
                                                  color:[FFStyle brightBlue] borderColor:[FFStyle white]];
    fbSignUp.frame = CGRectMake(15, 390, 290, 38);
    [fbSignUp addTarget:self action:@selector(signUpFacebook:) forControlEvents:UIControlEventTouchUpInside];
    [self.signUpView addSubview:fbSignUp];
    self.signUpFacebookButton = fbSignUp;
}

- (void)setupSignInView
{
    // background
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-splash-bg2.png"]];
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
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 130, 290, 60)];
    lab.font = [FFStyle lightFont:30];
    lab.text = NSLocalizedString(@"Sign In", nil);
    lab.backgroundColor = [UIColor clearColor];
    lab.textColor = [FFStyle white];
    [self.signInView addSubview:lab];
    
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
    un.text = @"sam@mustw.in"; // TODO: remove
    [self.signInView addSubview:un];
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
    pw.text = @"omgnowai"; // TODO: remove
    [self.signInView addSubview:pw];
    self.passwordSigninField = pw;
    
    // sign in buttons
    UIButton *signIn = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign In", nil)
                                                color:[FFStyle brightGreen] borderColor:[FFStyle white]];
    signIn.frame = CGRectMake(15, 310, 290, 38);
    [signIn addTarget:self action:@selector(signIn:) forControlEvents:UIControlEventTouchUpInside];
    [self.signInView addSubview:signIn];
    self.signInButton = signIn;
    
    UIButton *forgot = [UIButton buttonWithType:UIButtonTypeCustom];
    [forgot setTitle:NSLocalizedString(@"Forgot Your Password?", nil) forState:UIControlStateNormal];
    forgot.frame = CGRectMake(15, 355, 290, 50);
    forgot.titleLabel.font = [FFStyle lightFont:19];
    forgot.titleLabel.textAlignment = NSTextAlignmentCenter;
    [forgot setTitleColor:[FFStyle white] forState:UIControlStateNormal];
    [forgot setTitleColor:[FFStyle darkerColorForColor:[FFStyle white]] forState:UIControlStateHighlighted];
    [forgot addTarget:self action:@selector(forgotPassword:) forControlEvents:UIControlEventTouchUpInside];
    [self.signInView addSubview:forgot];
}

// IBACTIONS -----------------------------------------------------------------------------------------------------------

- (void)signInHeaderSwitch:(id)sender
{
    [UIView transitionFromView:self.signUpView
                        toView:self.signInView
                      duration:.35
                       options:UIViewAnimationOptionTransitionFlipFromRight
                    completion:nil];
}

- (void)signUpHeaderSwitch:(id)sender
{
    [UIView transitionFromView:self.signInView
                        toView:self.signUpView
                      duration:.35
                       options:UIViewAnimationOptionTransitionFlipFromRight
                    completion:nil];
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
    
    if (!self.usernameSignupField.text.length) {
        error = NSLocalizedString(@"Pleaes provide your username", nil);
        goto validate_error;
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
    
    FFAlertView *progressAlert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Finding Account", @"creating account")
                                                           messsage:NSLocalizedString(@"In a few short moments you'll be on your way!",
                                                                                      @"on sign in, tells the user they will be signed in soon")
                                                       loadingStyle:FFAlertViewLoadingStylePlain];
    [progressAlert showInView:self.view];
    SBSession *sesh = [SBSession sessionWithEmailAddress:self.usernameSigninField.text userClass:[FFUser class]];
    [sesh loginWithEmail:self.usernameSigninField.text password:self.passwordSigninField.text success:^(id user) {
        [progressAlert hide];
        [[self.view findFirstResponder] resignFirstResponder];
        self.session = sesh;
        [SBSession setLastUsedSession:sesh];
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
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:nil
                                                   messsage:NSLocalizedString(@"Looking for your account...", nil)
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void) {
        // TODO: actually do this...
        [alert hide];
        FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Check your email", nil)
                                                        message:NSLocalizedString(@"We sent you an email with a link to reset your passord.", nil)
                                              cancelButtonTitle:nil
                                                okayButtonTitle:NSLocalizedString(@"Okay", nil)
                                                       autoHide:YES];
        [alert showInView:self.view];
    });
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
        error = NSLocalizedString(@"Pleaes provide your username", nil);
        goto validate_error;
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
                                                           messsage:NSLocalizedString(@"In a few short moments you'll be on your way!",
                                                                                      @"on singup, tells the user they will be signed up soon")
                                                       loadingStyle:FFAlertViewLoadingStylePlain];
    [progressAlert showInView:self.view];
    
    SBSession *sesh = [SBSession sessionWithEmailAddress:self.usernameSignupField.text userClass:[FFUser class]];
    
    FFUser *user = [[FFUser alloc] initWithSession:sesh];
    user.email = self.usernameSignupField.text;
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
        [SBSession setLastUsedSession:sesh];
        self.session = sesh;
        [self performSegueWithIdentifier:@"GotoHome" sender:nil];
    };
    
    [sesh registerAndLoginUser:user password:password success:onSuccess failure:onErr];
}

- (void)signUpFacebook:(id)sender
{
    
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
        CGRect frame = CGRectOffset(self.view.frame, 0, -100);
        
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
        CGRect frame = CGRectOffset(self.view.frame, 0, 100);
        
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
    if (!__balanceView) {
        __balanceView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 105, 41)];
        __balanceView.backgroundColor = [UIColor clearColor];
        __balanceView.opaque = YES;
        
        UILabel *balance = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 100, 44)];
        balance.backgroundColor = [UIColor clearColor];
        balance.font = [FFStyle regularFont:12];
        balance.textColor = [UIColor whiteColor];
        balance.text = NSLocalizedString(@"Balance", nil);
        [__balanceView addSubview:balance];
        
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(56, 10, 49, 24)];
        background.backgroundColor = [FFStyle brightGreen];
        background.layer.borderWidth = 1;
        background.layer.borderColor = [FFStyle white].CGColor;
        background.layer.cornerRadius = 4;
        [__balanceView addSubview:background];
        
        UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 49, 24)];
        value.backgroundColor = [UIColor clearColor];
        value.font = [FFStyle boldFont:14];
        value.textColor = [FFStyle white];
        value.textAlignment = NSTextAlignmentCenter;
        value.text = @"1000";
        [background addSubview:value];
    }
    return __balanceView;
}

@end


@implementation UIViewController (FFSessionController)

- (FFSessionViewController *)sessionController {
    UIViewController *iter = self.parentViewController;
    while (iter) {
        if ([iter isKindOfClass:[FFSessionViewController class]]) {
            return (FFSessionViewController *)iter;
        } else if (iter.parentViewController && iter.parentViewController != iter) {
            iter = iter.parentViewController;
        } else {
            iter = nil;
        }
    }
    if (!iter) {
        iter = self.presentingViewController;
        while (iter) {
            if ([iter isKindOfClass:[FFSessionViewController class]]) {
                return (FFSessionViewController *)iter;
            } else if (iter.presentingViewController && iter.presentingViewController != iter) {
                iter = iter.presentingViewController;
            } else {
                iter = nil;
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
