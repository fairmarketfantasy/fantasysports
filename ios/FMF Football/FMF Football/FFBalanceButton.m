//
//  FFBalanceButton.m
//  FMF Football
//
//  Created by Samuel Sutch on 10/3/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBalanceButton.h"
#import <QuartzCore/QuartzCore.h>


@implementation FFBalanceButton
{
    UILabel *lab;
    BOOL shouldPoll;
}

- (id)initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        self.frame = CGRectMake(0, 0, 107, 44);
        self.backgroundColor = [UIColor clearColor];
        self.opaque = YES;
        
        UILabel *balance = [[UILabel alloc] initWithFrame:CGRectMake(20, 0, 100, 44)];
        balance.backgroundColor = [UIColor clearColor];
        balance.font = [FFStyle regularFont:12];
        balance.textColor = [UIColor whiteColor];
        balance.text = NSLocalizedString(@"Balance", nil);
        balance.userInteractionEnabled = NO;
        [self addSubview:balance];
        
        UIView *background = [[UIView alloc] initWithFrame:CGRectMake(66, 10, 49, 24)];
        background.backgroundColor = [FFStyle brightGreen];
        background.layer.borderWidth = 1;
        background.layer.borderColor = [FFStyle white].CGColor;
        background.layer.cornerRadius = 4;
        background.userInteractionEnabled = NO;
        [self addSubview:background];
        
        UILabel *value = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 49, 24)];
        value.backgroundColor = [UIColor clearColor];
        value.font = [FFStyle boldFont:14];
        value.textColor = [FFStyle white];
        value.textAlignment = NSTextAlignmentCenter;
        value.text = @"0";
        lab = value;
        value.userInteractionEnabled = NO;
        [background addSubview:value];
    }
    return self;
}

- (void)willMoveToSuperview:(UIView *)newSuperview
{
    [super willMoveToSuperview:newSuperview];
    if (newSuperview) {
        shouldPoll = YES;
        [self poll];
    } else {
        shouldPoll = NO;
    }
}

- (void)poll
{
    if (!shouldPoll) {
        return;
    }
    if (self.dataSource && [self.dataSource respondsToSelector:@selector(balanceViewGetBalance:)]) {
        lab.text = [NSString stringWithFormat:@"%d", [self.dataSource balanceViewGetBalance:self]];
    }
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self poll];
    });
}

/*
// Only override drawRect: if you perform custom drawing.
// An empty implementation adversely affects performance during animation.
- (void)drawRect:(CGRect)rect
{
    // Drawing code
}
*/

@end
