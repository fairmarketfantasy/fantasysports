//
//  FFContest.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFContest.h"
#import <SBData/NSDictionary+Convenience.h>

@implementation FFContest

@dynamic awayTeam;
@dynamic gameDay;
@dynamic gameTime;
@dynamic homeTeam;
@dynamic network;
@dynamic seasonType;
@dynamic seasonWeek;
@dynamic seasonYear;
@dynamic statsId;
@dynamic scheduled;

+ (NSString *)tableName { return @"ffcontest"; }

+ (void)load { [self registerModel:self]; }

+ (NSString *)bulkPath { return @"/games"; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{
                @"awayTeam":    @"away_team",
                @"gameDay":     @"game_day",
                @"gameTime":    @"game_time",
                @"homeTeam":    @"home_team",
                @"network":     @"network",
                @"seasonType":  @"season_type",
                @"seasonWeek":  @"season_week",
                @"seasonYear":  @"season_year",
                @"statsId":     @"stats_id",
                @"status":      @"status"
            }];
}

@end
