//
//  FFAlertView.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFAlertView.h"
#import <QuartzCore/QuartzCore.h>
#import "UIView+FindFirstResponder.h"

@interface FFAlertView ()

@property (nonatomic) UIButton *cancelbutton;
@property (nonatomic) UIButton *okayButton;
@property (nonatomic) UIView *contentView;
@property (nonatomic) UILabel *titleLabel;
@property (nonatomic) UILabel *bodyLabel;
@property (nonatomic) UIView *buttonBox;

- (void)_sleep; // makes controls inactive
- (void)_awake; // makes controls active
@property (nonatomic) UIView *autoHiddenFirstResponder;
- (void)_setupHorizontalButtonsCancelTitle:(NSString *)cancelTitle okayTitle:(NSString *)okayTitle;
- (void)_setupVerticalButtons:(NSArray *)buttons;
+ (void)_configureBlueButton:(UIButton *)button;
+ (void)_configureRedButton:(UIButton *)button;

@property (nonatomic) NSArray *customButtons;

@end


@implementation FFAlertView

- (UIView *)initWithTitle:(NSString *)title message:(NSString *)message
{
    self = [super init];
    if (self) {
        self.translatesAutoresizingMaskIntoConstraints = NO;
        self.backgroundColor = [UIColor colorWithWhite:0 alpha:.75];
        
        self.autoHide = NO;
        self.autoHideKeyboard = YES;
        
        // this is the view that contains the content and controls
        UIView *innerView = self.contentView = [[UIView alloc] init];
        innerView.translatesAutoresizingMaskIntoConstraints = NO;
        innerView.backgroundColor = [FFStyle lightGrey];
        
        // button box first, since it is easy...
        UIView *buttonBox = self.buttonBox = [[UIView alloc] init];
        buttonBox.translatesAutoresizingMaskIntoConstraints = NO;
        
        [innerView addSubview:buttonBox];
        [innerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[buttonBox]-10-|" options:0 metrics:nil
                                                                            views:NSDictionaryOfVariableBindings(buttonBox)]];
        
        [self addSubview:innerView];
        [self addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-10-[innerView]-10-|" options:0 metrics:nil
                                                                       views:NSDictionaryOfVariableBindings(innerView)]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:innerView attribute:NSLayoutAttributeCenterX
                                                         relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterX
                                                        multiplier:1.0 constant:0]];
        [self addConstraint:[NSLayoutConstraint constraintWithItem:innerView attribute:NSLayoutAttributeCenterY
                                                         relatedBy:NSLayoutRelationEqual toItem:self attribute:NSLayoutAttributeCenterY
                                                        multiplier:1.0 constant:0]];
        
        // now do the title and body
        UILabel *titleLabel = nil;
        UILabel *bodyLabel = nil;
        if (title != nil) {
            titleLabel = self.titleLabel = [[UILabel alloc] init];
            titleLabel.text = title;
            titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
            titleLabel.textAlignment = NSTextAlignmentCenter;
            titleLabel.backgroundColor = [UIColor clearColor];
            titleLabel.font = [FFStyle regularFont:24];
            titleLabel.textColor = [FFStyle black];
            titleLabel.numberOfLines = 4;
            titleLabel.preferredMaxLayoutWidth = 200;
            [innerView addSubview:titleLabel];
            [innerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[titleLabel]-|" options:0
                                                                              metrics:nil views:NSDictionaryOfVariableBindings(titleLabel)]];
        }
        if (message != nil) {
            bodyLabel = self.bodyLabel = [[UILabel alloc] init];
            bodyLabel.text = message;
            bodyLabel.translatesAutoresizingMaskIntoConstraints = NO;
            bodyLabel.textAlignment = NSTextAlignmentCenter;
            bodyLabel.backgroundColor = [UIColor clearColor];
            bodyLabel.font = [FFStyle regularFont:18];
            bodyLabel.textColor = [FFStyle black];
            bodyLabel.numberOfLines = 8;
            bodyLabel.preferredMaxLayoutWidth = 240;
            [innerView addSubview:bodyLabel];
            [innerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-[bodyLabel]-|" options:0
                                                                              metrics:nil views:NSDictionaryOfVariableBindings(bodyLabel)]];
        }
        
        // set overall vertical layout
        NSDictionary *vertPlaces = nil;
        NSString *vertLayoutString = nil;
        if (title != nil && message != nil) {
            vertLayoutString = @"V:|-10-[titleLabel]-10-[bodyLabel]-10-[buttonBox]-10-|";
            vertPlaces = NSDictionaryOfVariableBindings(titleLabel, bodyLabel, buttonBox);
        } else if (title != nil && message == nil) {
            vertLayoutString = @"V:|-10-[titleLabel]-10-[buttonBox]-10-|";
            vertPlaces = NSDictionaryOfVariableBindings(titleLabel, buttonBox);
        } else if (title == nil && message != nil) {
            vertLayoutString = @"V:|-10-[bodyLabel]-10-[buttonBox]-10-|";
            vertPlaces = NSDictionaryOfVariableBindings(bodyLabel, buttonBox);
        } else if (title == nil && message == nil) {
            vertLayoutString = @"V:|-10-[buttonBox]-10-|";
            vertPlaces = NSDictionaryOfVariableBindings(buttonBox);
        }
        [innerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vertLayoutString options:0
                                                                          metrics:nil views:vertPlaces]];
        
        [self _sleep];
    }
    return self;
}

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
  cancelButtonTitle:(NSString *)cancelTitle
    okayButtonTitle:(NSString *)okayTitle
           autoHide:(BOOL)shouldAutoHide
{
    if (cancelTitle == nil && okayTitle == nil) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Either okay title or cancel title must be filled in." userInfo:nil];
    }
    if (title == nil && message == nil) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Either title or message must be filled in." userInfo:nil];
    }
    
    self = [self initWithTitle:title message:message];
    
    if (self) {
        self.autoHide = shouldAutoHide;
        if (cancelTitle || okayTitle) {
            [self _setupHorizontalButtonsCancelTitle:cancelTitle okayTitle:okayTitle];
        }
    }
    return self;
}

- (id)initWithError:(NSError *)error
              title:(NSString *)title
  cancelButtonTitle:(NSString *)cancelTitle
    okayButtonTitle:(NSString *)okayTitle
           autoHide:(BOOL)shouldAutohide
{
    NSString *tit = nil;
    NSString *msg = nil;
    
    // try to stringify the error somehow
    NSDictionary *data = [error userInfo];
    if (data != nil) {
        NSString *locDesc = [data objectForKey:NSLocalizedDescriptionKey];
        if (locDesc != nil) {
            msg = locDesc;
            goto got_msg;
        }
        NSString *errorKey = [data objectForKey:@"error"];
        if (errorKey != nil) {
            msg = errorKey;
            goto got_msg;
        }
    } else {
        msg = NSLocalizedString(@"An uknown error occurred.", @"unknown error msg");
    }
    
got_msg:
    
    if (title) {
        tit = title;
    } else {
        tit = msg;
        msg = nil;
    }
    
    return [self initWithTitle:tit message:msg cancelButtonTitle:cancelTitle
               okayButtonTitle:okayTitle autoHide:shouldAutohide];
}

- (id)initWithTitle:(NSString *)title
            message:(NSString *)message
            buttons:(NSArray *)buttons
{
    self = [self initWithTitle:title message:message];
    if (self) {
        if (buttons.count) {
            [self _setupVerticalButtons:buttons];
        }
    }
    return self;
}

- (id)initWithTitle:(NSString *)title
           messsage:(NSString *)message
       loadingStyle:(FFAlertViewLoadingStyle)loadingStyle
{
    self = [self initWithTitle:title message:message];
    if (self) {
        if (loadingStyle == FFAlertViewLoadingStylePlain) {
            UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:
                                                UIActivityIndicatorViewStyleWhiteLarge];
            spinner.color = [FFStyle black];
            spinner.translatesAutoresizingMaskIntoConstraints = NO;
            [self.buttonBox addSubview:spinner];
            [self.buttonBox addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[spinner]|" options:0 metrics:nil
                                                                                     views:NSDictionaryOfVariableBindings(spinner)]];
            [self.buttonBox addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[spinner]|" options:0 metrics:nil
                                                                                     views:NSDictionaryOfVariableBindings(spinner)]];
            [spinner startAnimating];
        }
    }
    return self;
}

- (void)_setupHorizontalButtonsCancelTitle:(NSString *)cancelTitle okayTitle:(NSString *)okayTitle
{
    UIButton *cancelButton = nil;
    UIButton *okayButton = nil;
    if (cancelTitle) {
        cancelButton = self.cancelbutton = [FFStyle coloredButtonWithText:cancelTitle
                                                                    color:[FFStyle brightRed]
                                                              borderColor:[FFStyle white]];
        [[self class] _configureRedButton:cancelButton];
        [cancelButton addTarget:self action:@selector(cancelButtonTouched:) forControlEvents:UIControlEventTouchUpInside];
        [self.buttonBox addSubview:cancelButton];
    }
    if (okayTitle != nil) {
        okayButton = self.okayButton = [FFStyle coloredButtonWithText:okayTitle
                                                                color:[FFStyle brightBlue]
                                                          borderColor:[FFStyle white]];
        [[self class] _configureBlueButton:okayButton];
        [okayButton addTarget:self action:@selector(okayButtonTouched:) forControlEvents:UIControlEventTouchUpInside];
        [self.buttonBox addSubview:okayButton];
    }
    
    NSDictionary *buttonPlaces = nil;
    NSString *buttonLayoutString = nil;
    if (okayTitle != nil && cancelButton != nil) {
        // we have both, so layout both side to side
        buttonLayoutString = @"H:|[cancelButton(==okayButton)]-[okayButton(==cancelButton)]|";
        buttonPlaces = NSDictionaryOfVariableBindings(okayButton, cancelButton);
    } else if (okayTitle != nil && cancelButton == nil) {
        buttonLayoutString = @"H:|[okayButton]|";
        buttonPlaces = NSDictionaryOfVariableBindings(okayButton);
    } else if (okayTitle == nil && cancelButton != nil) {
        buttonLayoutString = @"H:|[cancelButton]|";
        buttonPlaces = NSDictionaryOfVariableBindings(cancelButton);
    }
    if (okayTitle != nil) {
        [self.buttonBox addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[okayButton(>=38)]|"
                                                                               options:0 metrics:nil views:buttonPlaces]];
    }
    if (cancelTitle != nil) {
        [self.buttonBox addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[cancelButton(>=38)]|"
                                                                               options:0 metrics:nil views:buttonPlaces]];
    }
    
    [self.buttonBox addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:buttonLayoutString
                                                                           options:0 metrics:nil views:buttonPlaces]];
}

- (void)_setupVerticalButtons:(NSArray *)buttons
{
    NSMutableDictionary *buttonMapping = [NSMutableDictionary new];
    NSMutableString *vertLayout = [[NSMutableString alloc] initWithString:@"V:|"];
    NSUInteger i = 0;
    for (UIButton *butt in buttons) {
        [self.buttonBox addSubview:butt];
        [self.buttonBox addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[butt]|" options:0 metrics:nil
                                                                                 views:NSDictionaryOfVariableBindings(butt)]];
        NSString *key = [NSString stringWithFormat:@"button%d", i];
        [buttonMapping setObject:butt forKey:key];
        [vertLayout appendFormat:@"[%@(>=38)]%@", key, ((i+1)==buttons.count ? @"" : @"-10-")];
        i++;
    }
    [vertLayout appendString:@"|"];
    [self.buttonBox addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:vertLayout options:0
                                                                           metrics:nil views:buttonMapping]];
}

+ (void)_configureRedButton:(FFCustomButton *)button
{
    button.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    button.translatesAutoresizingMaskIntoConstraints = NO;
}

+ (void)_configureBlueButton:(FFCustomButton *)button
{
    button.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    button.translatesAutoresizingMaskIntoConstraints = NO;
}

+ (FFCustomButton *)blueButtonTitled:(NSString *)str
{
    FFCustomButton *ret = [FFStyle coloredButtonWithText:str color:[FFStyle brightBlue] borderColor:[FFStyle white]];
    [self _configureBlueButton:ret];
    return ret;
}

+ (FFCustomButton *)redButtonTitled:(NSString *)str
{
    FFCustomButton *ret = [FFStyle coloredButtonWithText:str color:[FFStyle brightRed] borderColor:[FFStyle white]];
    [self _configureRedButton:ret];
    return ret;
}

- (void)showInView:(UIView *)view
{
    self.alpha = 0;
    if (self.autoHideKeyboard && self.previousFirstResponder == nil) {
        UIView *firstResponder = [view findFirstResponder];
        if (firstResponder != nil) {
            self.autoHiddenFirstResponder = firstResponder;
        }
    }
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 1;
        [self _awake];
    }];
    [view addSubview:self];
    [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[self]|" options:0 metrics:nil
                                                                   views:NSDictionaryOfVariableBindings(self)]];
    [view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[self]|" options:0 metrics:nil
                                                                   views:NSDictionaryOfVariableBindings(self)]];
}

- (void)hide
{
    [self _sleep];
    self.autoHiddenFirstResponder = nil;
    [UIView animateWithDuration:0.25 animations:^{
        self.alpha = 0;
    } completion:^(BOOL finished) {
        if (finished) {
            [self removeFromSuperview];
        }
    }];
}

- (void)cancelButtonTouched:(id)sender
{
    if (self.autoHide) {
        [self hide];
    }
    if (self.onCancel != nil) {
        self.onCancel(self);
    }
}

- (void)okayButtonTouched:(id)sender
{
    if (self.autoHide) {
        [self hide];
    }
    if (self.onOkay != nil) {
        self.onOkay(self);
    }
}

- (void)_sleep
{
    if (self.previousFirstResponder && [self.previousFirstResponder respondsToSelector:@selector(becomeFirstResponder)]) {
        [self.previousFirstResponder becomeFirstResponder];
    }
    if (self.autoHiddenFirstResponder && [self.autoHiddenFirstResponder respondsToSelector:@selector(becomeFirstResponder)]) {
        [self.autoHiddenFirstResponder becomeFirstResponder];
    }
    self.cancelbutton.userInteractionEnabled = NO;
    self.cancelbutton.userInteractionEnabled = NO;
}

- (void)_awake
{
    if (self.previousFirstResponder && [self.previousFirstResponder respondsToSelector:@selector(resignFirstResponder)]) {
        [self.previousFirstResponder resignFirstResponder];
    }
    if (self.autoHiddenFirstResponder && [self.autoHiddenFirstResponder respondsToSelector:@selector(resignFirstResponder)]) {
        [self.autoHiddenFirstResponder resignFirstResponder];
    }
    self.cancelbutton.userInteractionEnabled = YES;
    self.cancelbutton.userInteractionEnabled = YES;
}

@end
