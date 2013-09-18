//
//  FFBaseViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/17/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBaseViewController.h"
#import "FFStyle.h"

@interface FFBaseViewController ()

@end

@implementation FFBaseViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)showBanner:(NSString *)text target:(id)target selector:(SEL)sel
{
    FFCustomButton *v = [FFCustomButton buttonWithType:UIButtonTypeCustom];
    v.frame = CGRectMake(0, self.view.frame.origin.y-44, self.view.frame.size.width, 44);
    [v setBackgroundColor:[FFStyle brightGreen] forState:UIControlStateNormal];
    [v setBackgroundColor:[FFStyle darkerColorForColor:[FFStyle brightGreen]] forState:UIControlStateHighlighted];
    if (target != nil && sel != NULL) {
        [v addTarget:target action:sel forControlEvents:UIControlEventTouchUpInside];
    }
    [v addTarget:self action:@selector(closeBanner:) forControlEvents:UIControlEventTouchUpInside];
    [self.view.superview addSubview:v];
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, self.view.frame.size.width-30, 44)];
    lab.backgroundColor = [UIColor clearColor];
    lab.font = [FFStyle regularFont:14];
    lab.textColor = [FFStyle white];
    lab.text = text;
    lab.numberOfLines = 2;
    lab.userInteractionEnabled = NO;
    
    [v addSubview:lab];
    v.alpha = 0;
    
    UIImageView *close = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"bannerclose.png"]];
    close.frame = CGRectMake(v.frame.size.width-16, v.frame.size.height-16, 8, 16);
    close.contentMode = UIViewContentModeCenter;
    [v addSubview:close];
    
    CGRect viewFrame = CGRectMake(0, self.view.frame.origin.y+44, self.view.frame.size.width, self.view.frame.size.height-44);
    
    [UIView animateWithDuration:.25 animations:^{
        self.view.frame = viewFrame;
        v.alpha = 1;
        v.frame = CGRectOffset(v.frame, 0, 44);
    }];
}

- (void)closeBanner:(UIButton *)banner
{
    CGRect viewFrame = CGRectMake(0, self.view.frame.origin.y-44, self.view.frame.size.width, self.view.frame.size.height+44);
    [UIView animateWithDuration:.25 animations:^{
        self.view.frame = viewFrame;
        banner.alpha = 0;
        banner.frame = CGRectOffset(banner.frame, 0, -44);
    } completion:^(BOOL finished) {
        if (finished) {
            [banner removeFromSuperview];
        }
    }];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (self.navigationController && self.navigationController.viewControllers.count && self.navigationController.viewControllers[0] != self) {
        self.navigationItem.leftBarButtonItem = [FFStyle backBarItemForController:self];
    }
}

- (BOOL)shouldAutorotate
{
    return NO;
}

- (NSUInteger)supportedInterfaceOrientations
{
    return UIInterfaceOrientationPortrait;
}

@end
