//
//  FFBaseViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/17/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBaseViewController.h"
#import "FFStyle.h"


@interface FFDrawerBackingView : UIView
@property (nonatomic) BOOL frameLocked;
@end


@interface FFBaseViewController () <UIGestureRecognizerDelegate>
@property (nonatomic) UITableView *_resizingTableView;
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

- (void)showBanner:(NSString *)text target:(id)target selector:(SEL)sel animated:(BOOL)animated
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
    
    //CGRect viewFrame = CGRectMake(0, self.view.frame.origin.y+44, self.view.frame.size.width, self.view.frame.size.height-44);
    
    void (^ani)(void) = ^{
        //self.view.frame = viewFrame;
        v.alpha = 1;
        v.frame = CGRectOffset(v.frame, 0, 44);
    };
    
    if (animated) {
        [UIView animateWithDuration:.25 animations:ani];
    } else {
        ani();
    }
}

- (void)closeBannerAnimated:(BOOL)animated
{
    // TODO: respect animated
    if (self.banner) {
        [self closeBanner:self.banner];
    }
}

- (void)closeBanner:(UIView *)banner
{
    //CGRect viewFrame = CGRectMake(0, self.view.frame.origin.y-44, self.view.frame.size.width, self.view.frame.size.height+44);
    [UIView animateWithDuration:.25 animations:^{
        //self.view.frame = viewFrame;
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

- (void)showControllerInDrawer:(FFDrawerViewController *)vc minimizedViewController:(FFDrawerViewController *)mvc animated:(BOOL)animated
{
    [self showControllerInDrawer:vc minimizedViewController:mvc inView:self.view animated:NO];
}

- (void)showControllerInDrawer:(FFDrawerViewController *)vc
       minimizedViewController:(FFDrawerViewController *)mvc
                        inView:(UIView *)view
               resizeTableView:(UITableView *)tableView
                      animated:(BOOL)animated
{
    __resizingTableView = tableView;
    [self showControllerInDrawer:vc minimizedViewController:mvc animated:YES];
}

- (void)showControllerInDrawer:(FFDrawerViewController *)vc
       minimizedViewController:(FFDrawerViewController *)mvc
                        inView:(UIView *)view
                      animated:(BOOL)animated
{
    if (_minimizedDrawerController || _drawerController) {
        NSLog(@"trying to show a drawer when there already is one %@ %@", vc, mvc);
        return;
    }
    NSParameterAssert(vc != nil); // require the full vc, but minimized vc is optional
    
    _drawerIsMinimized = NO;
    
    _drawerController = vc;
    vc.view.frame = CGRectMake(0, 0, view.frame.size.width, DRAWER_HEIGHT);
    
    CGRect viewFrame = view.frame;
    viewFrame.size.height -= DRAWER_HEIGHT;
    
    UISwipeGestureRecognizer *minSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                             action:@selector(swipeDrawer:)];
    minSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionDown;
    minSwipeRecognizer.delegate = self;
    [vc.view addGestureRecognizer:minSwipeRecognizer];
    
    if (mvc) {
        _minimizedDrawerController = mvc;
        FFDrawerBackingView *mview = [[FFDrawerBackingView alloc] initWithFrame:
                                      CGRectMake(0, viewFrame.size.height, viewFrame.size.width, DRAWER_MINIMIZED_HEIGHT)];
        mview.frameLocked = YES;
        mview.alpha = 0;
        [mview addSubview:mvc.view];
        [view addSubview:mview];
        
        mvc.view.frame = CGRectMake(0, 0, viewFrame.size.width, DRAWER_MINIMIZED_HEIGHT);
        
        UISwipeGestureRecognizer *maxSwipeRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self
                                                                                                 action:@selector(swipeMinimizedDrawer:)];
        maxSwipeRecognizer.direction = UISwipeGestureRecognizerDirectionUp;
        maxSwipeRecognizer.delegate = self;
        [mvc.view addGestureRecognizer:maxSwipeRecognizer];
    }
    
    [vc viewWillAppear:YES];
    
    FFDrawerBackingView *mview = [[FFDrawerBackingView alloc] initWithFrame:
                                 CGRectMake(0, viewFrame.size.height, viewFrame.size.width, DRAWER_HEIGHT)];
    [mview addSubview:vc.view];
    [view addSubview:mview];
    
    void (^ani)(void) = ^{
        view.frame = CGRectMake(0, viewFrame.size.height, viewFrame.size.width, DRAWER_HEIGHT);
        mview.frameLocked = YES; // ss: hackity hack
        view.frame = viewFrame;
        if (__resizingTableView) {
            __resizingTableView.contentInset = UIEdgeInsetsMake(0, 0, DRAWER_HEIGHT, 0);
        }
    };
    
    void (^finish)(BOOL) = ^(BOOL finished) {
        if (finished) {
            [vc viewDidAppear:YES];
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:.25 animations:ani completion:finish];
    } else {
        ani();
        finish(YES);
    }
}

- (void)swipeDrawer:(UISwipeGestureRecognizer *)recognizer
{
    [self minimizeDrawerAnimated:YES];
}

- (void)swipeMinimizedDrawer:(UISwipeGestureRecognizer *)recognizer
{
    [self maximizeDrawerAnimated:YES];
}

- (void)maximizeDrawerAnimated:(BOOL)animated
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
    
    CGRect viewFrame = _drawerController.view.superview.superview.frame;
    viewFrame.size.height = viewFrame.size.height + diff;
    
    [_minimizedDrawerController viewWillDisappear:animated];
    [_drawerController viewWillAppear:animated];
    
    [(FFDrawerBackingView *)_drawerController.view.superview setFrameLocked:NO];
    [(FFDrawerBackingView *)_minimizedDrawerController.view.superview setFrameLocked:NO];
    
    void (^ani)(void) = ^{
        _drawerController.view.superview.superview.frame = viewFrame;
        _drawerController.view.superview.frame = CGRectOffset(_drawerController.view.superview.frame, 0, diff);
        _drawerController.view.superview.alpha = 1;
        _minimizedDrawerController.view.superview.frame = CGRectOffset(_minimizedDrawerController.view.superview.frame, 0, diff);
        _minimizedDrawerController.view.superview.alpha = 0;
        if (__resizingTableView) {
            __resizingTableView.contentInset = UIEdgeInsetsMake(0, 0, DRAWER_HEIGHT, 0);
        }
    };
    void (^finish)(BOOL) = ^(BOOL finished) {
        if (finished) {
            [_minimizedDrawerController viewDidDisappear:animated];
            [_drawerController viewDidAppear:animated];
            [(FFDrawerBackingView *)_drawerController.view.superview setFrameLocked:YES];
            [(FFDrawerBackingView *)_minimizedDrawerController.view.superview setFrameLocked:YES];
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:.25 animations:ani completion:finish];
    } else {
        ani();
        finish(YES);
    }
}

- (void)minimizeDrawerAnimated:(BOOL)animated
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
    
    CGRect viewFrame = _drawerController.view.superview.superview.frame;
    viewFrame.size.height = viewFrame.size.height + diff;
    
    [_drawerController viewWillDisappear:animated];
    [_minimizedDrawerController viewWillAppear:animated];
    
    [(FFDrawerBackingView *)_drawerController.view.superview setFrameLocked:NO];
    [(FFDrawerBackingView *)_minimizedDrawerController.view.superview setFrameLocked:NO];

    void (^ani)(void) = ^{
        _drawerController.view.superview.superview.frame = viewFrame;
        _drawerController.view.superview.frame = CGRectOffset(_drawerController.view.superview.frame, 0, diff);
        _drawerController.view.superview.alpha = 0;
        _minimizedDrawerController.view.superview.frame = CGRectOffset(_minimizedDrawerController.view.superview.frame, 0, diff);
        _minimizedDrawerController.view.superview.alpha = 1;
        if (__resizingTableView) {
            __resizingTableView.contentInset = UIEdgeInsetsMake(0, 0, DRAWER_MINIMIZED_HEIGHT, 0);
        }
    };
    
    void (^finish)(BOOL) = ^(BOOL finished) {
        if (finished) {
            [_drawerController viewDidDisappear:animated];
            [_minimizedDrawerController viewDidAppear:animated];
            [(FFDrawerBackingView *)_drawerController.view.superview setFrameLocked:YES];
            [(FFDrawerBackingView *)_minimizedDrawerController.view.superview setFrameLocked:YES];
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:.25 animations:ani completion:finish];
    } else {
        ani();
        finish(YES);
    }
}

- (void)closeDrawerAnimated:(BOOL)animated
{
    if (!_drawerController) {
        NSLog(@"cant close a drawer that isn't showing...");
        return;
    }

    [(FFDrawerBackingView *)_drawerController.view.superview setFrameLocked:NO];
    if (self.minimizedDrawerController) {
        [(FFDrawerBackingView *)_minimizedDrawerController.view.superview setFrameLocked:NO];
    }

    FFDrawerViewController *drawer = (_drawerIsMinimized ? self.minimizedDrawerController : self.drawerController);
    [drawer viewWillDisappear:animated];

    CGFloat diff = (_drawerIsMinimized ? DRAWER_MINIMIZED_HEIGHT : DRAWER_HEIGHT);

    CGRect viewRect = drawer.view.superview.superview.frame;
    viewRect.size.height += diff;

    void (^ani)(void) = ^{
        drawer.view.superview.superview.frame = viewRect;
        drawer.view.superview.frame = CGRectOffset(drawer.view.superview.frame, 0, diff);
        drawer.view.superview.alpha = 0;
        if (__resizingTableView) {
            __resizingTableView.contentInset = UIEdgeInsetsZero;
        }
    };
    void (^finish)(BOOL) = ^(BOOL finished) {
        if (finished) {
            [drawer viewDidDisappear:animated];
            [(FFDrawerBackingView *)_drawerController.view.superview setFrameLocked:YES];
            [_drawerController.view.superview removeFromSuperview];
            if (self.minimizedDrawerController) {
                [(FFDrawerBackingView *)_minimizedDrawerController.view.superview setFrameLocked:YES];
                [_minimizedDrawerController.view.superview removeFromSuperview];
            }
            _drawerController = nil;
            _minimizedDrawerController = nil;
            _drawerIsMinimized = NO;
        }
    };

    if (animated) {
        [UIView animateWithDuration:.25 animations:ani completion:finish];
    } else {
        ani();
        finish(YES);
    }
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


@implementation FFDrawerBackingView

- (void)setFrame:(CGRect)frame
{
    if (!_frameLocked) {
        [super setFrame:frame];
    }
}

@end