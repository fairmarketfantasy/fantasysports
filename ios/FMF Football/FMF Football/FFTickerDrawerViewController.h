//
//  FFTickerDrawerViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFUser.h"

@interface FFTickerDrawerViewController : UIViewController

@property (nonatomic) SBSession *session;

- (void)getTicker:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)fail;

@end
