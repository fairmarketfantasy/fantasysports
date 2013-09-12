//
//  FFStyle.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FFStyle : NSObject

+ (UIColor *)darkGreen;
+ (UIColor *)white;
+ (UIColor *)greyBorder;

+ (UIFont *)blockFont:(int)size;
+ (UIFont *)regularFont:(int)size;
+ (UIFont *)italicFont:(int)size;

@end

CGRect CGRectCopyWithOrigin(CGRect r, CGPoint origin);