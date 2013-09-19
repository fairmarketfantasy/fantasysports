//
//  FFBaseViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/17/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface FFBaseViewController : UIViewController

@property (nonatomic, readonly) UIView *banner;
@property (nonatomic, readonly) UIViewController *drawerController;
@property (nonatomic, readonly) UIViewController *minimizedDrawerController;
@property (nonatomic, readonly) BOOL drawerIsMinimized;

- (void)showBanner:(NSString *)text target:(id)target selector:(SEL)sel animated:(BOOL)animated;
- (void)closeBannerAnimated:(BOOL)animated;

- (void)showControllerInDrawer:(UIViewController *)view minimizedViewController:(UIViewController *)view animated:(BOOL)animated;
- (void)maximizeDrawerAnimated:(BOOL)animated;
- (void)minimizeDrawerAnimated:(BOOL)animated;
- (void)closeDrawerAnimated:(BOOL)animated;

@end
