//
//  FFContestView.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFContestType.h"
#import "FFMarket.h"

@interface FFContestView : UIView

@property (nonatomic) FFContestType *contest;
@property (nonatomic) FFMarket *market;

@end
