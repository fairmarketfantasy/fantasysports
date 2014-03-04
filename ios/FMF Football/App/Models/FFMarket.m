//
//  FFMarket.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/23/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFMarket.h"
#import <SBData/NSDictionary+Convenience.h>
#import "NSDate+ISO8601.h"

@implementation FFMarket

@dynamic closedAt;
@dynamic marketDuration;
@dynamic name;
@dynamic openedAt;
@dynamic shadowBetRate;
@dynamic shadowBets;
@dynamic sportId;
@dynamic startedAt;
@dynamic state;
@dynamic totalBets;

+ (NSString *)tableName { return @"ffmarket"; }

+ (void)load { [self registerModel:self]; }

+ (NSString *)bulkPath { return @"/markets"; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{
                @"closedAt":        @"closed_at",
                @"marketDuration":  @"market_duration",
                @"name":            @"name",
                @"openedAt":        @"opened_at",
                @"shadowBetRate":   @"shadow_bet_rate",
                @"shadowBets":      @"shadow_bets",
                @"sportId":         @"sport_id",
                @"startedAt":       @"started_at",
                @"state":           @"state",
                @"totalBets":       @"total_bets"
            }];
}

+ (NSArray *)filteredMarkets:(NSArray *)markets
{
//    NSMutableArray *ret = [NSMutableArray arrayWithCapacity:2];
//    for (FFMarket *m in markets) {
//        if ([m.marketDuration isEqualToString:@"week"]) {
//            [ret addObject:m];
//            break;
//        }
//    }
//    for (FFMarket *m in markets) {
//        if ([m.marketDuration isEqualToString:@"day"]) {
//            [ret addObject:m];
//            break;
//        }
//    }
//    return [ret copy];
    return markets;
}

@end