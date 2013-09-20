//
//  FFSplashViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/12/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <SBData/SBData.h>
#import "FFUser.h"
#import "FFTickerMaximizedDrawerViewController.h"
#import "FFTickerMinimizedDrawerViewController.h"
#import "FFBaseViewController.h"

@interface FFSessionViewController : FFBaseViewController

@property (nonatomic) SBSession *session;

@property (nonatomic, readonly) UIView *balanceView;
@property (nonatomic, readonly) FFTickerMaximizedDrawerViewController *maximizedTicker;
@property (nonatomic, readonly) FFTickerMinimizedDrawerViewController *minimizedTicker;

@end


@interface UIViewController (FFSessionController)

- (FFSessionViewController *)sessionController;
- (SBSession *)session;

@end
