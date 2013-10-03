//
//  FFContest.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFContestType.h"
#import <SBData/NSDictionary+Convenience.h>

@implementation FFContestType

@dynamic buyIn;
@dynamic contestDescription;
@dynamic iconUrl;
@dynamic marketId;
@dynamic maxEntries;
@dynamic name;
@dynamic payoutDescription;
@dynamic payoutStructure;
@dynamic isPrivate;
@dynamic rake;
@dynamic userId;
@dynamic takesTokens;

+ (NSString *)tableName { return @"ffcontesttype"; }

+ (void)load { [self registerModel:self]; }

+ (NSString *)bulkPath { return @"/contests"; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{
                @"buyIn":               @"buy_in",
                @"contestDescription":  @"description",
                @"iconUrl":             @"icon_url",
                @"marketId":            @"market_id",
                @"maxEntries":          @"max_entries",
                @"name":                @"name",
                @"payoutDescription":   @"payout_description",
                @"payoutStructure":     @"payout_structure",
                @"isPrivate":           @"private",
                @"rake":                @"rake",
                @"userId":              @"user_id",
                @"takesTokens":         @"takes_tokens"
            }];
}

+ (NSArray *)indexes
{
    return [[super indexes] arrayByAddingObjectsFromArray:@[
            @[ @"marketId", @"userKey", @"takesTokens" ]]];
}

@end
