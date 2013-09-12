//
//  FFStyle.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FFStyle : NSObject

+ (UIColor *)darkGreen;
+ (UIColor *)white;
+ (UIColor *)brightGreen;
+ (UIColor *)brightBlue;
+ (UIColor *)greyBorder;

+ (UIFont *)blockFont:(int)size;
+ (UIFont *)regularFont:(int)size;
+ (UIFont *)italicFont:(int)size;
+ (UIColor *)lighterColorForColor:(UIColor *)c;
+ (UIColor *)darkerColorForColor:(UIColor *)c;

+ (UIButton *)clearButtonWithText:(NSString *)text borderColor:(UIColor *)color;
+ (UIButton *)coloredButtonWithText:(NSString *)text color:(UIColor *)color borderColor:(UIColor *)color;

@end

CGRect CGRectCopyWithOrigin(CGRect r, CGPoint origin);