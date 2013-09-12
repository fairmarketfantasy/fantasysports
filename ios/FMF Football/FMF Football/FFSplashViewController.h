//
//  FFSplashViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FFSplashViewController : UIViewController <UITextFieldDelegate>

@property (nonatomic) IBOutlet UITextField *usernameField;
@property (nonatomic) IBOutlet UITextField *passwordField;
@property (nonatomic) IBOutlet UIButton *signUpButton;
@property (nonatomic) IBOutlet UIButton *signUpFacebookButton;
@property (nonatomic) IBOutlet UIButton *signInButton;

- (IBAction)signIn:(id)sender;
- (IBAction)signUp:(id)sender;
- (IBAction)signUpFacebook:(id)sender;

@end
