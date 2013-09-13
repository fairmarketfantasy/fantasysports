//
//  FFSplashViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFSplashViewController.h"
#import <QuartzCore/QuartzCore.h>
#import "FFTextField.h"

@interface FFSplashViewController ()

@property (nonatomic) UIView *signInView;
@property (nonatomic) UIView *signUpView;

- (void)setupSignInView;
- (void)setupSignUpView;

@end

@implementation FFSplashViewController

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

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.signInView = [[UIView alloc] initWithFrame:CGRectOffset(self.view.frame, 0, -20)];
    [self setupSignInView];
    
    self.signUpView = [[UIView alloc] initWithFrame:CGRectOffset(self.view.frame, 0, -20)];
    [self setupSignUpView];
    
    [self.view addSubview:self.signInView];
    [self.view addSubview:self.signUpView];
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
    un.placeholder = NSLocalizedString(@"username", nil);
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
    un.placeholder = NSLocalizedString(@"username", nil);
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
    
}

- (void)forgotPassword:(id)sender
{
    
}

- (void)signUp:(id)sender
{
    
}

- (void)signUpFacebook:(id)sender
{
    
}

@end
