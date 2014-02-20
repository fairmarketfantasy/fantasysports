//
//  FFNavigationBarItemView.m
//  FMF Football
//
//  Created by Samuel Sutch on 10/3/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFNavigationBarItemView.h"

@implementation FFNavigationBarItemView

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code
    }
    return self;
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

//- (UIEdgeInsets)alignmentRectInsets {
//    UIEdgeInsets insets;
////    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
//    if ([self isLeftButton]) {
//        insets = UIEdgeInsetsMake(0, 12, 0, 0);
//    } else {
//        insets = UIEdgeInsetsMake(0, 0, 0, 12);
//    }
////    } else {
////        insets = UIEdgeInsetsZero;
////    }
//
//    return insets;
//}
//
//- (BOOL)isLeftButton {
//    return self.frame.origin.x < (self.superview.frame.size.width / 2);
//}

@end

@implementation FFNavigationBarItemButton

//- (UIEdgeInsets)alignmentRectInsets {
//    UIEdgeInsets insets;
//    //    if (SYSTEM_VERSION_LESS_THAN(@"7.0")) {
//    if ([self isLeftButton]) {
//        insets = UIEdgeInsetsMake(0, 12, 0, 0);
//    } else {
//        insets = UIEdgeInsetsMake(0, 0, 0, 12);
//    }
//    //    } else {
//    //        insets = UIEdgeInsetsZero;
//    //    }
//
//    return insets;
//}
//
//- (BOOL)isLeftButton {
//    return self.frame.origin.x < (self.superview.frame.size.width / 2);
//}

@end