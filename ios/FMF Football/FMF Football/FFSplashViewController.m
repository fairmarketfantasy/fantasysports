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
    
    // background
    UIImageView *bg = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-splash-bg.png"]];
    bg.contentMode = UIViewContentModeTop;
    bg.frame = self.view.frame;
    [self.view addSubview:bg];
    
    // header
    UIView *greenBg = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 30)];
    greenBg.backgroundColor = [FFStyle darkGreen];
    [self.view addSubview:greenBg];
    
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    [logo sizeToFit];
    logo.frame = CGRectCopyWithOrigin(logo.frame, CGPointMake(10, 7));
    [greenBg addSubview:logo];
    
    UIButton *signIn = [UIButton buttonWithType:UIButtonTypeCustom];
    signIn.layer.borderColor = [UIColor whiteColor].CGColor;
    signIn.layer.borderWidth = 1;
    signIn.layer.cornerRadius = 3;
    signIn.backgroundColor = [UIColor clearColor];
    signIn.titleLabel.font = [FFStyle blockFont:14];
    [signIn setTitle:@"Sign In" forState:UIControlStateNormal];
    signIn.frame = CGRectMake(self.view.frame.size.width - 85, 2, 70, 27);
    [greenBg addSubview:signIn];
    self.signInButton = signIn;
    
    UIImageView *marketingCopy = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-splash-copy.png"]];
    [marketingCopy sizeToFit];
    marketingCopy.center = CGPointMake(160, 120);
    [self.view addSubview:marketingCopy];
    
    // text inputs
    UITextField *un = [[FFTextField alloc] init];
//    un.borderStyle = uitextborderstyleno;
    un.layer.borderWidth = 1;
    un.frame = CGRectMake(15, 240, 290, 44);
    un.layer.borderColor = [FFStyle greyBorder].CGColor;
    un.backgroundColor = [FFStyle white];

    un.placeholder = NSLocalizedString(@"username", nil);
    [self.view addSubview:un];
    self.usernameField = un;
    
    UITextField *pw = [[FFTextField alloc] init];
//    pw.borderStyle = UITextBorderStyleLine;
    pw.layer.borderWidth = 1;
    pw.layer.borderColor = [FFStyle greyBorder].CGColor;
    pw.backgroundColor = [FFStyle white];

    pw.frame = CGRectMake(15, 300, 290, 44);
    pw.secureTextEntry = YES;
    pw.placeholder = NSLocalizedString(@"password", nil);
    [self.view addSubview:pw];
    self.passwordField = pw;
    
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view from its nib.
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
