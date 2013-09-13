//
//  FFSplashViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FFSplashViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic) IBOutlet UITextField *usernameSignupField;
@property (nonatomic) IBOutlet UITextField *passwordSignupField;
@property (nonatomic) IBOutlet UIButton *signUpButton;
@property (nonatomic) IBOutlet UIButton *signUpFacebookButton;
@property (nonatomic) IBOutlet UIButton *signInButton;
@property (nonatomic) IBOutlet UIButton *signInHeaderButton;
@property (nonatomic) IBOutlet UIButton *signUpHeaderButton;
@property (nonatomic) IBOutlet UITextField *usernameSigninField;
@property (nonatomic) IBOutlet UITextField *passwordSigninField;

- (IBAction)signInHeaderSwitch:(id)sender;
- (IBAction)signUpHeaderSwitch:(id)sender;
- (IBAction)signIn:(id)sender;
- (IBAction)signUp:(id)sender;
- (IBAction)signUpFacebook:(id)sender;
- (IBAction)forgotPassword:(id)sender;

@end
