//
//  FFBaseViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/17/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFDrawerViewController.h"
#import "FFMenuViewController.h"
#import <A2StoryboardSegueContext/A2StoryboardSegueContext.h>
#import "FFTickerDataSource.h"
#import "FFTickerMaximizedDrawerViewController.h"
#import "FFTickerMinimizedDrawerViewController.h"


@interface FFBaseViewController : UIViewController <FFMenuViewControllerDelegate>

@property (nonatomic) FFTickerMaximizedDrawerViewController *maximizedTicker;
@property (nonatomic) FFTickerMinimizedDrawerViewController *minimizedTicker;
@property (nonatomic) FFTickerDataSource *tickerDataSource;

@property (nonatomic, readonly) UIView *banner;
@property (nonatomic, readonly) FFDrawerViewController *drawerController;
@property (nonatomic, readonly) FFDrawerViewController *minimizedDrawerController;
@property (nonatomic, readonly) BOOL drawerIsMinimized;
@property (nonatomic, readonly) FFMenuViewController *menuController;

- (void)showBanner:(NSString *)text target:(id)target selector:(SEL)sel animated:(BOOL)animated;
- (void)closeBannerAnimated:(BOOL)animated;

- (void)showControllerInDrawer:(FFDrawerViewController *)view
       minimizedViewController:(FFDrawerViewController *)view
                      animated:(BOOL)animated;

- (void)showControllerInDrawer:(FFDrawerViewController *)vc
       minimizedViewController:(FFDrawerViewController *)mvc
                        inView:(UIView *)view
                      animated:(BOOL)animated;

- (void)showControllerInDrawer:(FFDrawerViewController *)vc
       minimizedViewController:(FFDrawerViewController *)mvc
                        inView:(UIView *)view
               resizeTableView:(UITableView *)tableView
                      animated:(BOOL)animated;

- (void)maximizeDrawerAnimated:(BOOL)animated;
- (void)minimizeDrawerAnimated:(BOOL)animated;
- (void)closeDrawerAnimated:(BOOL)animated;

- (void)showMenuController;
- (void)hideMenuController;

@end
