//
//  FFContestViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBaseViewController.h"
#import "FFContestType.h"
#import "FFMarket.h"

@interface FFContestViewController : FFBaseViewController

@property (nonatomic) FFContestType *contest;
@property (nonatomic) FFMarket *market;

@end
