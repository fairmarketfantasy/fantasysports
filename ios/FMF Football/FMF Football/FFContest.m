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

+ (NSString *)tableName { return @"ffcontest"; }

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
                @"userId":              @"userId"
            }];
}

@end
