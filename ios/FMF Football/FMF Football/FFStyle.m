//
//  FFStyle.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFStyle.h"

CGRect CGRectCopyWithOrigin(CGRect r, CGPoint origin) {
    CGRect rect = r;
    rect.origin.x = origin.x;
    rect.origin.y = origin.y;
    return rect;
}

@implementation FFStyle

+ (UIColor *)darkGreen
{
    return [UIColor colorWithRed:51.0/255.0 green:96.0/255.0 blue:48.0/255.0 alpha:1];
}

+ (UIColor *)white
{
    return [UIColor whiteColor];
}

+ (UIColor *)greyBorder
{
    return [UIColor colorWithWhite:.8 alpha:1];
}

+ (UIFont *)blockFont:(int)size
{
    return [UIFont fontWithName:@"Prohibition-Round" size:size];
}

+ (UIFont *)regularFont:(int)size
{
    return [UIFont fontWithName:@"HelveticaNeue-Light" size:size];
}

+ (UIFont *)italicFont:(int)size
{
    return [UIFont fontWithName:@"HelveticaNeue-LightItalic" size:size];
}

@end
