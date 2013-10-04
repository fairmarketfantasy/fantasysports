//
//  FFAlertView.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void(^FFAlertViewBlock)(id);

typedef enum {
    FFAlertViewLoadingStylePlain
} FFAlertViewLoadingStyle;

@interface FFAlertView : UIView

// calls onCancel(FFAlertView=self)
@property (nonatomic, strong) FFAlertViewBlock onCancel;
// calls onOkay(FFAlertView=self)
@property (nonatomic, strong) FFAlertViewBlock onOkay;
//whether or not to automatically hide the view when a button is touched (default=NO)
@property (nonatomic) BOOL autoHide;
@property (nonatomic) BOOL autoHideKeyboard;
@property (nonatomic, weak) id previousFirstResponder;
@property (nonatomic) BOOL autoRemoveFromSuperview;

// create an alert view that must be manually dismissed in code
- (id)initWithTitle:(NSString *)title
            message:(NSString *)message;

// createa an alert view with up to two side-by-side buttons
- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
  cancelButtonTitle:(NSString *)cancelTitle
    okayButtonTitle:(NSString *)okayTitle
           autoHide:(BOOL)shouldAutoHide;

// does thes same as above but populates the title and message with the provided error
- (id)initWithError:(NSError *)error
              title:(NSString *)title
  cancelButtonTitle:(NSString *)cancelTitle
    okayButtonTitle:(NSString *)okayTitle
           autoHide:(BOOL)shouldAutohide;

// creates an alert view with a series of vertical buttons
- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
            buttons:(NSArray *)buttons;

- (id)initWithTitle:(NSString *)title
           messsage:(NSString *)message
       loadingStyle:(FFAlertViewLoadingStyle)loadingStyle;

- (void)showInView:(UIView *)view;
- (void)hide;

+ (FFCustomButton *)redButtonTitled:(NSString *)str;
+ (FFCustomButton *)blueButtonTitled:(NSString *)str;
+ (FFCustomButton *)greyButtonTitled:(NSString *)str;

@end
