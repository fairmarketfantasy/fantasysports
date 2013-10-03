//
//  FFUser.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFUser.h"
#import <SBData/NSDictionary+Convenience.h>

@implementation FFUser

@dynamic name;
@dynamic imageUrl;
@dynamic balance;
@dynamic joinDate;
@dynamic winPercentile;
@dynamic tokenBalance;
@dynamic email;
@dynamic totalPoints;
@dynamic totalWins;

+ (NSString *)tableName { return @"ffuser"; }

+ (void)load { [self registerModel:self]; }

- (NSString *)listPath { return @"/users.json"; }

- (NSString *)detailPathSpec { return @"/users.json"; }

// customize the to the nonstandard way the /users endpoint works
- (AFHTTPClientParameterEncoding)paramterEncoding { return AFFormURLParameterEncoding; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{
                @"userId":          @"id",
                @"name":            @"name",
                @"imageUrl":        @"image_url",
                @"balance":         @"balance",
                @"tokenBalance":    @"token_balance",
                @"totalPoints":     @"total_points",
                @"totalWins":       @"total_wins",
                @"winPercentile":   @"win_percentile",
                @"email":           @"email",
                @"joinDate":        @"joined_at"
            }];
}

- (NSDictionary *)toNetworkRepresentation
{
    return @{ @"user": [super toNetworkRepresentation] };
}

@end
