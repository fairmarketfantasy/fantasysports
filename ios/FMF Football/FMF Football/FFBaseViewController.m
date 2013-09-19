//
//  FFBaseViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/17/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBaseViewController.h"
#import "FFStyle.h"

@interface FFBaseViewController () <UIGestureRecognizerDelegate>

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
    if (_banner) {
        NSLog(@"trying to show a banner when there already is one %@ %@ -> %@", text, target, NSStringFromSelector(sel));
        return;
    }
    FFCustomButton *v = [FFCustomButton buttonWithType:UIButtonTypeCustom];
    _banner = v;
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

- (void)closeBanner
{
    if (self.banner) {
        [self closeBanner:self.banner];
    }
}

- (void)closeBanner:(UIView *)banner
{
    CGRect viewFrame = CGRectMake(0, self.view.frame.origin.y-44, self.view.frame.size.width, self.view.frame.size.height+44);
    [UIView animateWithDuration:.25 animations:^{
        self.view.frame = viewFrame;
        banner.alpha = 0;
        banner.frame = CGRectOffset(banner.frame, 0, -44);
    } completion:^(BOOL finished) {
        if (finished) {
            [banner removeFromSuperview];
            _banner = nil;
        }
    }];
}

#define DRAWER_HEIGHT 95
#define DRAWER_MINIMIZED_HEIGHT 48

- (void)showControllerInDrawer:(UIViewController *)vc minimizedViewController:(UIViewController *)mvc
{
    if (_minimizedDrawerController || _drawerController) {
        NSLog(@"trying to show a drawer when there already is one %@ %@", vc, mvc);
        return;
    }
    NSParameterAssert(vc != nil); // require the full vc, but minimized vc is optional
    
    _drawerIsMinimized = NO;
    
    _drawerController = vc;
    vc.view.frame = CGRectMake(0, self.view.frame.size.height, self.view.frame.size.width, DRAWER_HEIGHT);
    
    UISwipeGestureRecognizer *minSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(swipeDrawer:)];
    minSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
    minSwipeRecognizer.delegate = self;
    [vc.view addGestureRecognizer:minSwipeRecognizer];
    
    if (mvc) {
        _minimizedDrawerController = mvc;
        mvc.view.frame = CGRectMake(0, self.view.frame.size.height-DRAWER_HEIGHT, self.view.frame.size.width, DRAWER_MINIMIZED_HEIGHT);
        mvc.view.alpha = 0;
        
        UISwipeGestureRecognizer *maxSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                                 action:@selector(swipeMinimizedDrawer:)];
        maxSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
        maxSwipeRecognizer.delegate = self;
        [mvc.view addGestureRecognizer:maxSwipeRecognizer];
    }
    
    CGRect viewFrame = self.view.frame;
    viewFrame.size.height -= DRAWER_HEIGHT;
    
    [vc viewWillAppear:YES];
    [self.view.superview addSubview:vc.view];
    [UIView animateWithDuration:.25 animations:^{
        vc.view.frame = CGRectOffset(vc.view.frame, 0, -DRAWER_HEIGHT);
        self.view.frame = viewFrame;
    } completion:^(BOOL finished) {
        [vc viewDidAppear:YES];
    }];
}

- (void)swipeDrawer:(UISwipeGestureRecognizer *)recognizer
{
    [self minimizeDrawer];
}

- (void)swipeMinimizedDrawer:(UISwipeGestureRecognizer *)recognizer
{
    [self maximizeDrawer];
}

- (void)maximizeDrawer
{
    if (!_minimizedDrawerController) {
        NSLog(@"tried to maximize drawer but there is no minimized controller... how did we even get here?");
        return;
    }
    if (!_drawerIsMinimized) {
        NSLog(@"tried to maximize drawer that is already maximized");
        return;
    }
    
    _drawerIsMinimized = NO;
    
    CGFloat diff = DRAWER_MINIMIZED_HEIGHT - DRAWER_HEIGHT;
    
    CGRect viewFrame = self.view.frame;
    viewFrame.size.height = viewFrame.size.height + diff;
    
    [_minimizedDrawerController viewWillDisappear:YES];
    [_drawerController viewWillAppear:YES];
    [self.view.superview addSubview:_drawerController.view];
    
    [UIView animateWithDuration:.25 animations:^{
        self.view.frame = viewFrame;
        _drawerController.view.frame = CGRectOffset(_drawerController.view.frame, 0, diff);
        _drawerController.view.alpha = 1;
        _minimizedDrawerController.view.frame = CGRectOffset(_minimizedDrawerController.view.frame, 0, diff);
        _minimizedDrawerController.view.alpha = 0;
    } completion:^(BOOL finished) {
        [_minimizedDrawerController viewDidDisappear:YES];
        [_minimizedDrawerController.view removeFromSuperview];
        [_drawerController viewDidAppear:YES];
    }];
}

- (void)minimizeDrawer
{
    if (!_minimizedDrawerController) {
        NSLog(@"tried to minimize drawer but there is no minimized controller");
        return;
    }
    if (_drawerIsMinimized) {
        NSLog(@"tried to minimize the drawer but it is already minimized");
        return;
    }
    
    _drawerIsMinimized = YES;
    
    CGFloat diff = DRAWER_HEIGHT - DRAWER_MINIMIZED_HEIGHT;
    
    CGRect viewFrame = self.view.frame;
    viewFrame.size.height = viewFrame.size.height + diff;
    
    [_drawerController viewWillDisappear:YES];
    [_minimizedDrawerController viewWillAppear:YES];
    [self.view.superview addSubview:_minimizedDrawerController.view];

    [UIView animateWithDuration:.25 animations:^{
        self.view.frame = viewFrame;
        _drawerController.view.frame = CGRectOffset(_drawerController.view.frame, 0, diff);
        _drawerController.view.alpha = 0;
        _minimizedDrawerController.view.frame = CGRectOffset(_minimizedDrawerController.view.frame, 0, diff);
        _minimizedDrawerController.view.alpha = 1;
    } completion:^(BOOL finished) {
        [_drawerController viewDidDisappear:YES];
        [_drawerController.view removeFromSuperview];
        [_minimizedDrawerController viewDidAppear:YES];
    }];
}

- (void)closeDrawer
{
    
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
