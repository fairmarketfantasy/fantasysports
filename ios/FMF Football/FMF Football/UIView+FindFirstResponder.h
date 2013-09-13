//
//  UIView+FindFirstResponder.h
//  CoTap
//
//  Created by Samuel Sutch on 2/13/13.
//  Copyright (c) 2013 CoTap. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface UIView (FindFirstResponder)

- (UIView *)findFirstResponder;
- (UIView *)findFirstResponderOfView:(UIView *)view;

@end
