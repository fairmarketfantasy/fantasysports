//
//  FFStyle.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

#define SYSTEM_VERSION_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedSame)
#define SYSTEM_VERSION_GREATER_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedDescending)
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] == NSOrderedAscending)
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v) ([[[UIDevice currentDevice] systemVersion] compare:v options:NSNumericSearch] != NSOrderedDescending)

#define IS_SMALL_DEVICE (([[UIScreen mainScreen] bounds].size.height < 568) ? YES : NO)

@class FFCustomButton;

@interface FFStyle : NSObject

+ (UIColor*)darkGreen;
+ (UIColor*)white;
+ (UIColor*)brightGreen;
+ (UIColor*)brightBlue;
+ (UIColor*)greyBorder;
+ (UIColor*)lightGrey;
+ (UIColor*)greyTextColor;
+ (UIColor*)darkGreyTextColor;
+ (UIColor*)black;
+ (UIColor*)brightRed;
+ (UIColor*)yellowErrorColor;
+ (UIColor*)tableViewSeparatorColor;
+ (UIColor*)brightOrange;
+ (UIColor*)tableViewSectionHeaderColor;

+ (UIFont*)blockFont:(int)size;
+ (UIFont*)regularFont:(int)size;
+ (UIFont*)italicFont:(int)size;
+ (UIFont*)lightFont:(int)size;
+ (UIFont*)boldFont:(int)size;
+ (UIFont*)mediumFont:(int)size;

+ (UIColor*)lighterColorForColor:(UIColor*)c;
+ (UIColor*)darkerColorForColor:(UIColor*)c;

+ (UIButton*)clearButtonWithText:(NSString*)text borderColor:(UIColor*)color;
+ (NSArray*)clearNavigationBarButtonWithText:(NSString*)text
                                 borderColor:(UIColor*)color
                                      target:(id)target
                                    selector:(SEL)selector
                               leftElseRight:(BOOL)left;
+ (FFCustomButton*)coloredButtonWithText:(NSString*)text color:(UIColor*)color borderColor:(UIColor*)color;
+ (NSArray*)backBarItemsForController:(UIViewController*)controller;

+ (void)customizeAppearance;

@end

// CUSTOM UI CLASSES ---------------------------------------------------------------------------------------------------

@interface FFCustomButton : UIButton {
@private
    NSMutableDictionary* backgroundStates;
@public
}

- (void)setBackgroundColor:(UIColor*)_backgroundColor forState:(UIControlState)_state;
- (UIColor*)backgroundColorForState:(UIControlState)_state;

@end

// UTILITY FUNCTIONS ---------------------------------------------------------------------------------------------------

CGRect CGRectCopyWithOrigin(CGRect r, CGPoint origin);