//
//  FFStyle.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFStyle.h"
#import <QuartzCore/QuartzCore.h>
#import "FFNavigationBarItemView.h"

// HELPER FUNCTIONS ----------------------------------------------------------------------------------------------------

CGRect CGRectCopyWithOrigin(CGRect r, CGPoint origin)
{
    CGRect rect = r;
    rect.origin.x = origin.x;
    rect.origin.y = origin.y;
    return rect;
}

// STYLE ---------------------------------------------------------------------------------------------------------------

@implementation FFStyle

// COLORS --------------------------------------------------------------------------------------------------------------

+ (UIColor*)darkGreen
{
    return [UIColor colorWithRed:51.0 / 255.0
                           green:96.0 / 255.0
                            blue:48.0 / 255.0
                           alpha:1];
}

+ (UIColor*)white
{
    return [UIColor whiteColor];
}

+ (UIColor*)greyBorder
{
    return [UIColor colorWithWhite:.8
                             alpha:1];
}

+ (UIColor*)brightGreen
{
    return [UIColor colorWithRed:75.0 / 255.0
                           green:172.0 / 255.0
                            blue:69.0 / 255.0
                           alpha:1];
}

+ (UIColor*)brightBlue
{
    return [UIColor colorWithRed:59.0 / 255.0
                           green:104.0 / 255.0
                            blue:1
                           alpha:1];
}

+ (UIColor*)lightGrey
{
    return [UIColor colorWithWhite:.8
                             alpha:1];
}

+ (UIColor*)black
{
    return [UIColor blackColor];
}

+ (UIColor*)brightRed
{
    return [UIColor colorWithRed:190.0 / 255.0
                           green:30.0 / 255.0
                            blue:45.0 / 255.0
                           alpha:1];
}

+ (UIColor*)yellowErrorColor
{
    return [UIColor yellowColor]; // TODO: this
}

+ (UIColor*)greyTextColor
{
    return [UIColor colorWithWhite:.4
                             alpha:1];
}

+ (UIColor*)darkGreyTextColor
{
    return [UIColor colorWithWhite:.25
                             alpha:1];
}

+ (UIColor*)tableViewSeparatorColor
{
    return [UIColor colorWithWhite:.85
                             alpha:1];
}

+ (UIColor*)tableViewSectionHeaderColor
{
    return [UIColor colorWithRed:34.0 / 255.0
                           green:34.0 / 255.0
                            blue:34.0 / 255.0
                           alpha:1];
}

+ (UIColor*)brightOrange
{
    return [UIColor colorWithRed:246.0 / 255.0
                           green:146.0 / 255.0
                            blue:30.0 / 255.0
                           alpha:1];
}

// FONTS ---------------------------------------------------------------------------------------------------------------

+ (UIFont*)blockFont:(int)size
{
    return [UIFont fontWithName:@"Prohibition-Round"
                           size:size];
}

+ (UIFont*)regularFont:(int)size
{
    return [UIFont fontWithName:@"HelveticaNeue-Light"
                           size:size];
}

+ (UIFont*)italicFont:(int)size
{
    return [UIFont fontWithName:@"HelveticaNeue-LightItalic"
                           size:size];
}

+ (UIFont*)lightFont:(int)size
{
    return [UIFont fontWithName:@"HelveticaNeue-UltraLight"
                           size:size];
}

+ (UIFont*)boldFont:(int)size
{
    return [UIFont fontWithName:@"HelveticaNeue-Bold"
                           size:size];
}

+ (UIFont*)mediumFont:(int)size
{
    return [UIFont fontWithName:@"HelveticaNeue-Medium"
                           size:size];
}

// UI CONSTRUCTORS -----------------------------------------------------------------------------------------------------

+ (UIButton*)clearButtonWithText:(NSString*)text borderColor:(UIColor*)color
{
    UIButton* b = [UIButton buttonWithType:UIButtonTypeCustom];
    b.layer.borderColor = color.CGColor;
    b.layer.borderWidth = 1;
    b.layer.cornerRadius = 3;
    b.layer.masksToBounds = YES;
    [b setBackgroundImage:[UIImage imageNamed:@"0-percent.png"]
                  forState:UIControlStateNormal];
    [b setBackgroundImage:[UIImage imageNamed:@"40-percent.png"]
                  forState:UIControlStateHighlighted];
    b.titleLabel.font = [FFStyle blockFont:14];
    [b setTitle:text
        forState:UIControlStateNormal];
    return b;
}

//+ (UIButton *)clearNavigationBarButtonWithText:(NSString *)text borderColor:(UIColor *)color
//+ (NSArray *)clearNavigationBarButtonWithText:(NSString *)text borderColor:(UIColor *)color leftElseRight:(BOOL)left
+ (NSArray*)clearNavigationBarButtonWithText:(NSString*)text
                                 borderColor:(UIColor*)color
                                      target:(id)target
                                    selector:(SEL)selector
                               leftElseRight:(BOOL)left
{
    UIButton* b = [FFNavigationBarItemButton buttonWithType:UIButtonTypeCustom];
    b.frame = CGRectMake(0, 0, 65, 27);
    b.layer.borderColor = color.CGColor;
    b.layer.borderWidth = 1;
    b.layer.cornerRadius = 3;
    b.layer.masksToBounds = YES;
    [b setBackgroundImage:[UIImage imageNamed:@"0-percent.png"]
                  forState:UIControlStateNormal];
    [b setBackgroundImage:[UIImage imageNamed:@"40-percent.png"]
                  forState:UIControlStateHighlighted];
    b.titleLabel.font = [FFStyle blockFont:14];
    [b setTitle:text
        forState:UIControlStateNormal];
    [b addTarget:target
                  action:selector
        forControlEvents:UIControlEventTouchUpInside];

    UIBarButtonItem* item = [[UIBarButtonItem alloc] initWithCustomView:b];

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        UIBarButtonItem* spacer = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                                target:nil
                                                                                action:NULL];
        spacer.width = -8;
        if (left) {
            return @[
                spacer,
                item
            ];
        } else {
            UIView* cont = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 65, 27)];
            cont.backgroundColor = [UIColor clearColor];
            b.frame = CGRectOffset(b.frame, 7, 0);
            [cont addSubview:b];
            return @[
                [[UIBarButtonItem alloc] initWithCustomView:cont]
            ];
            //            return @[item, spacer];
        }
    } else {
        return @[
            item
        ];
    }
}

+ (UIButton*)coloredButtonWithText:(NSString*)text color:(UIColor*)color borderColor:(UIColor*)borderColor
{
    FFCustomButton* b = [[FFCustomButton alloc] init];
    b.layer.borderColor = borderColor.CGColor;
    b.layer.borderWidth = 1;
    b.layer.cornerRadius = 3;
    [b setBackgroundColor:color
                  forState:UIControlStateNormal];
    [b setBackgroundColor:[self darkerColorForColor:color]
                  forState:UIControlStateHighlighted];
    b.titleLabel.font = [FFStyle blockFont:14];
    [b setTitle:text
        forState:UIControlStateNormal];
    return b;
}

+ (NSArray*)backBarItemsForController:(UIViewController*)controller
{
    UIView* leftView = [[FFNavigationBarItemButton alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    UIButton* gmenu = [UIButton buttonWithType:UIButtonTypeCustom];
    [gmenu setImage:[UIImage imageNamed:@"backbtn.png"]
           forState:UIControlStateNormal];
    [gmenu addTarget:controller.navigationController
                  action:@selector(popViewControllerAnimated:)
        forControlEvents:UIControlEventTouchUpInside];
    gmenu.frame = CGRectMake(-2, 0, 35, 44);
    [leftView addSubview:gmenu];
    UIImageView* logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    logo.frame = CGRectMake(32, 13, 150, 19);
    [leftView addSubview:logo];

    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        UIBarButtonItem* item = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                              target:nil
                                                                              action:NULL];
        item.width = -16;

        return @[
            item,
            [[UIBarButtonItem alloc] initWithCustomView:leftView]
        ];
    } else {
        return @[
            [[UIBarButtonItem alloc] initWithCustomView:leftView]
        ];
    }
}

+ (UIColor*)lighterColorForColor:(UIColor*)c
{
    float r, g, b, w, a;
    if ([c getRed:&r
             green:&g
              blue:&b
             alpha:&a]) {
        return [UIColor colorWithRed:MIN(r + 0.2, 1.0)
                               green:MIN(g + 0.2, 1.0)
                                blue:MIN(b + 0.2, 1.0)
                               alpha:a];
    } else if ([c getWhite:&w
                      alpha:&a]) {
        return [UIColor colorWithWhite:MIN(w + 0.2, 1.0)
                                 alpha:a];
    }
    return nil;
}

+ (UIColor*)darkerColorForColor:(UIColor*)c
{
    float r, g, b, w, a;
    if ([c getRed:&r
             green:&g
              blue:&b
             alpha:&a]) {
        return [UIColor colorWithRed:MAX(r - 0.2, 0.0)
                               green:MAX(g - 0.2, 0.0)
                                blue:MAX(b - 0.2, 0.0)
                               alpha:a];
    } else if ([c getWhite:&w
                      alpha:&a]) {
        return [UIColor colorWithWhite:MAX(w - 0.2, 0.0)
                                 alpha:a];
    }
    return nil;
}

// customize uiappearance ----------------------------------------------------------------------------------------------
+ (void)customizeAppearance
{
    [[UINavigationBar appearance] setBackgroundImage:[UIImage imageNamed:@"darkgreen.png"]
                                       forBarMetrics:UIBarMetricsDefault];
    [[UINavigationBar appearance] setBackgroundImage:[UIImage imageNamed:@"darkgreen.png"]
                                       forBarMetrics:UIBarMetricsLandscapePhone];

    if ([[UINavigationBar appearance] respondsToSelector:@selector(setBarTintColor:)]) {
        [[UINavigationBar appearance] setBarTintColor:[FFStyle darkGreen]];
    }
    [[UINavigationBar appearance] setTintColor:[FFStyle white]];

    [[UINavigationBar appearance] setTitleTextAttributes:@{
                                                             UITextAttributeTextColor : [FFStyle white],
                                                             UITextAttributeTextShadowColor : [UIColor colorWithWhite:0
                                                                                                                alpha:.15],
                                                             UITextAttributeTextShadowOffset : [NSValue valueWithUIOffset:UIOffsetMake(0, -1)],
                                                             UITextAttributeFont : [FFStyle regularFont:22]
                                                         }];

    [[UINavigationBar appearance] setTitleVerticalPositionAdjustment:0
                                                       forBarMetrics:UIBarMetricsDefault];

    if ([[UIToolbar appearance] respondsToSelector:@selector(setBarTintColor:)]) {
        [[UIToolbar appearance] setBarTintColor:[FFStyle darkGreen]];
    }
    [[UIToolbar appearance] setTintColor:[FFStyle white]];

    [[UIToolbar appearance] setBackgroundImage:[UIImage imageNamed:@"darkgreen.png"]
                            forToolbarPosition:UIToolbarPositionAny
                                    barMetrics:UIBarMetricsDefault];
    [[UIToolbar appearance] setBackgroundImage:[UIImage imageNamed:@"darkgreen.png"]
                            forToolbarPosition:UIToolbarPositionAny
                                    barMetrics:UIBarMetricsLandscapePhone];
}

@end

@implementation FFCustomButton

- (void)setBackgroundColor:(UIColor*)_backgroundColor forState:(UIControlState)_state
{
    if (backgroundStates == nil) {
        backgroundStates = [[NSMutableDictionary alloc] init];
    }

    [backgroundStates setObject:_backgroundColor
                         forKey:[NSNumber numberWithInt:_state]];

    if (self.backgroundColor == nil) {
        [self setBackgroundColor:_backgroundColor];
    }
}

- (UIColor*)backgroundColorForState:(UIControlState)_state
{
    return [backgroundStates objectForKey:[NSNumber numberWithInt:_state]];
}

#pragma mark -
#pragma mark Touches

- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event
{
    [super touchesBegan:touches
              withEvent:event];

    UIColor* selectedColor = [backgroundStates objectForKey:[NSNumber numberWithInt:UIControlStateHighlighted]];
    if (selectedColor) {
        CATransition* animation = [CATransition animation];
        [animation setType:kCATransitionFade];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        [self.layer addAnimation:animation
                          forKey:@"EaseOut"];
        self.backgroundColor = selectedColor;
    }
}

- (void)touchesCancelled:(NSSet*)touches withEvent:(UIEvent*)event
{
    [super touchesCancelled:touches
                  withEvent:event];

    UIColor* normalColor = [backgroundStates objectForKey:[NSNumber numberWithInt:UIControlStateNormal]];
    if (normalColor) {
        CATransition* animation = [CATransition animation];
        [animation setType:kCATransitionFade];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        [self.layer addAnimation:animation
                          forKey:@"EaseOut"];
        self.backgroundColor = normalColor;
    }
}

- (void)touchesEnded:(NSSet*)touches withEvent:(UIEvent*)event
{
    [super touchesEnded:touches
              withEvent:event];

    UIColor* normalColor = [backgroundStates objectForKey:[NSNumber numberWithInt:UIControlStateNormal]];
    if (normalColor) {
        CATransition* animation = [CATransition animation];
        [animation setType:kCATransitionFade];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut]];
        [self.layer addAnimation:animation
                          forKey:@"EaseOut"];
        self.backgroundColor = normalColor;
    }
}

@end