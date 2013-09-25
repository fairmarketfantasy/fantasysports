//
//  FFContestView.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFContest.h"
#import "FFMarket.h"

@interface FFContestView : UIView

@property (nonatomic) FFContest *contest;
@property (nonatomic) FFMarket *market;

@end
