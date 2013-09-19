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

- (void)showBanner:(NSString *)text target:(id)target selector:(SEL)sel;
- (void)closeBanner;

- (void)showControllerInDrawer:(UIViewController *)view minimizedViewController:(UIViewController *)view;
- (void)maximizeDrawer;
- (void)minimizeDrawer;
- (void)closeDrawer;

@end
