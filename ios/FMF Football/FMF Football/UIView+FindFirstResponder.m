//
//  UIView+FindFirstResponder.m
//  CoTap
//
//  Created by Samuel Sutch on 2/13/13.
//  Copyright (c) 2013 CoTap. All rights reserved.
//

#import "UIView+FindFirstResponder.h"

@implementation UIView (FindFirstResponder)

- (UIView *)findFirstResponder
{
    return [self findFirstResponderOfView:self];
}

- (UIView *)findFirstResponderOfView:(UIView *)view
{
    if (!view.isFirstResponder) {
        for (UIView *subview in view.subviews) {
            UIView *subviewFirst = [self findFirstResponderOfView:subview];
            if (subviewFirst != nil) {
                return subviewFirst;
            }
        }
    } else {
        return view;
    }
    return nil;
}

@end
