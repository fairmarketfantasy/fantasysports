//
//  FFStyle.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FFCustomButton;

@interface FFStyle : NSObject

+ (UIColor *)darkGreen;
+ (UIColor *)white;
+ (UIColor *)brightGreen;
+ (UIColor *)brightBlue;
+ (UIColor *)greyBorder;
+ (UIColor *)lightGrey;
+ (UIColor *)greyTextColor;
+ (UIColor *)darkGreyTextColor;
+ (UIColor *)black;
+ (UIColor *)brightRed;
+ (UIColor *)yellowErrorColor;
+ (UIColor *)tableViewSeparatorColor;
+ (UIColor *)brightOrange;
+ (UIColor *)tableViewSectionHeaderColor;

+ (UIFont *)blockFont:(int)size;
+ (UIFont *)regularFont:(int)size;
+ (UIFont *)italicFont:(int)size;
+ (UIFont *)lightFont:(int)size;
+ (UIFont *)boldFont:(int)size;
+ (UIFont *)mediumFont:(int)size;

+ (UIColor *)lighterColorForColor:(UIColor *)c;
+ (UIColor *)darkerColorForColor:(UIColor *)c;

+ (UIButton *)clearButtonWithText:(NSString *)text borderColor:(UIColor *)color;
+ (FFCustomButton *)coloredButtonWithText:(NSString *)text color:(UIColor *)color borderColor:(UIColor *)color;
+ (UIBarButtonItem *)backBarItemForController:(UIViewController *)controller;

+ (void)customizeAppearance;

@end

// CUSTOM UI CLASSES ---------------------------------------------------------------------------------------------------

@interface FFCustomButton : UIButton
{
@private
    NSMutableDictionary *backgroundStates;
@public
}

- (void)setBackgroundColor:(UIColor *) _backgroundColor forState:(UIControlState)_state;
- (UIColor *)backgroundColorForState:(UIControlState)_state;

@end

// UTILITY FUNCTIONS ---------------------------------------------------------------------------------------------------

CGRect CGRectCopyWithOrigin(CGRect r, CGPoint origin);