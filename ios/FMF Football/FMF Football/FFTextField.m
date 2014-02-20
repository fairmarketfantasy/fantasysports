//
//  FFTextField.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTextField.h"

@implementation FFTextField

- (id)initWithCoder:(NSCoder*)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
        [self _privateInit];
    }
    return self;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        [self _privateInit];
    }
    return self;
}

#define INSET_X 5
#define INSET_Y 10
#define INSET_Y_COMPENSATION 0
#define INSET_Y_COMPENSATION_EDITING 2

- (void)_privateInit
{
    self.font = [FFStyle regularFont:self.font.pointSize];
    self.placeholderColor = [UIColor lightGrayColor];
    self.placeholderFont = [FFStyle italicFont:self.font.pointSize];
    self.textInsetX = INSET_X;
    self.textInsetY = INSET_Y;
}

- (CGRect)textRectForBounds:(CGRect)bounds
{
    CGFloat compensation = INSET_Y_COMPENSATION;
    if (self.editing) {
        compensation = INSET_Y_COMPENSATION_EDITING;
    }
    CGFloat addedWidth = 0;
    if (self.leftView) {
        addedWidth = self.leftView.frame.size.width + 5;
    }
    return CGRectMake(self.textInsetX + addedWidth,
                      self.textInsetY - compensation,
                      bounds.size.width - self.textInsetX - self.textInsetX / 2 - addedWidth,
                      bounds.size.height - self.textInsetY);
}

- (CGRect)placeholderRectForBounds:(CGRect)bounds
{
    CGFloat addedWidth = 0;
    if (self.leftView) {
        addedWidth = self.leftView.frame.size.width + 5;
    }
    CGFloat subtractedWidth = 0;
    if (self.rightView) {
        subtractedWidth = self.rightView.frame.size.width + 5;
    }
    return CGRectMake(self.textInsetX + addedWidth,
                      self.textInsetY + 1,
                      bounds.size.width - self.textInsetX - addedWidth - subtractedWidth,
                      bounds.size.height - self.textInsetY);
}

- (CGRect)leftViewRectForBounds:(CGRect)bounds
{
    CGRect newBounds = [super leftViewRectForBounds:bounds];
    newBounds.origin.x += self.textInsetX;
    return newBounds;
}

- (CGRect)rightViewRectForBounds:(CGRect)bounds
{
    CGRect newBounds = [super rightViewRectForBounds:bounds];
    newBounds.origin.x -= self.textInsetX / 2;
    return newBounds;
}

- (CGRect)editingRectForBounds:(CGRect)bounds
{
    CGFloat compensation = INSET_Y_COMPENSATION;
    if (self.editing) {
        compensation = INSET_Y_COMPENSATION_EDITING;
    }
    CGFloat addedWidth = 0;
    if (self.leftView) {
        addedWidth = self.leftView.frame.size.width + 5;
    }
    CGFloat subtractedWidth = 0;
    if (self.rightView) {
        subtractedWidth = self.rightView.frame.size.width + 5;
    }
    return CGRectMake(self.textInsetX + addedWidth,
                      self.textInsetY - compensation,
                      bounds.size.width - self.textInsetX - self.textInsetX / 2 - addedWidth - subtractedWidth,
                      bounds.size.height - self.textInsetY);
}

- (void)drawPlaceholderInRect:(CGRect)rect
{
    [self.placeholderColor setFill];
    [self.placeholder drawInRect:rect
                        withFont:[FFStyle italicFont:16]];
}

@end