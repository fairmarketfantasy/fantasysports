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
    // background
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-splash-bg.png"]];
    bg.contentMode = UIViewContentModeTop;
    bg.frame = self.view.frame;
    [self.view addSubview:bg];
    
    // header
    UIView *greenBg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 45)];
    greenBg.backgroundColor = [FFStyle darkGreen];
    [self.view addSubview:greenBg];
    
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    [logo sizeToFit];
    logo.frame = CGRectCopyWithOrigin(logo.frame, CGPointMake(10, 15));
    [greenBg addSubview:logo];
    
    UIButton *signIn = [FFStyle clearButtonWithText:NSLocalizedString(@"Sign In", nil) borderColor:[FFStyle white]];
    signIn.frame = CGRectMake(self.view.frame.size.width - 80, 7, 70, 30);
    [greenBg addSubview:signIn];
    [signIn addTarget:self action:@selector(signIn:) forControlEvents:UIControlEventTouchUpInside];
    self.signInButton = signIn;
    
    UIImageView *marketingCopy = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-splash-copy.png"]];
    [marketingCopy sizeToFit];
    marketingCopy.center = CGPointMake(160, 140);
    [self.view addSubview:marketingCopy];
    
    // text inputs
    UITextField *un = [[FFTextField alloc] init];
    un.layer.borderWidth = 1;
    un.frame = CGRectMake(15, 225, 290, 44);
    un.layer.borderColor = [FFStyle greyBorder].CGColor;
    un.backgroundColor = [FFStyle white];
    un.delegate = self;
    un.placeholder = NSLocalizedString(@"username", nil);
    [self.view addSubview:un];
    self.usernameField = un;
    
    UITextField *pw = [[FFTextField alloc] init];
    pw.layer.borderWidth = 1;
    pw.layer.borderColor = [FFStyle greyBorder].CGColor;
    pw.backgroundColor = [FFStyle white];
    pw.delegate = self;
    pw.frame = CGRectMake(15, 280, 290, 44);
    pw.secureTextEntry = YES;
    pw.placeholder = NSLocalizedString(@"password", nil);
    [self.view addSubview:pw];
    self.passwordField = pw;
    
    // sign in buttons
    UIButton *signUp = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign Up", nil) color:[FFStyle brightGreen] borderColor:[FFStyle white]];
    signUp.frame = CGRectMake(15, 340, 290, 38);
    [signUp addTarget:self action:@selector(signUp:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:signUp];
    self.signUpButton = signUp;
    
    UIButton *fbSignUp = [FFStyle coloredButtonWithText:NSLocalizedString(@"Sign Up With Facebook", nil) color:[FFStyle brightBlue] borderColor:[FFStyle white]];
    fbSignUp.frame = CGRectMake(15, 390, 290, 38);
    [fbSignUp addTarget:self action:@selector(signUpFacebook:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:fbSignUp];
    self.signUpFacebookButton = fbSignUp;
}

- (void)signUp:(id)sender
{
    
}

- (void)signIn:(id)sender
{
    
}

- (void)signUpFacebook:(id)sender
{
    
}

@end
