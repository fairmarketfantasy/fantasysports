//
//  FFMarket.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/23/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "SBDataObject.h"
#import <SBData/SBTypes.h>

@interface FFMarket : SBDataObject

@property (nonatomic) SBDate    *closedAt;
@property (nonatomic) NSString  *marketDuration;
@property (nonatomic) NSString  *name;
@property (nonatomic) SBDate    *openedAt;
@property (nonatomic) SBFloat   *shadowBetRate;
@property (nonatomic) SBFloat   *shadowBets;
@property (nonatomic) SBInteger *sportId;
@property (nonatomic) SBDate    *startedAt;
@property (nonatomic) NSString  *state;
@property (nonatomic) SBFloat   *totalBets;

+ (NSArray *)filteredMarkets:(NSArray *)markets;

@end
