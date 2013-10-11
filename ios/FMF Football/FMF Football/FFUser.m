//
//  FFUser.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFUser.h"
#import <SBData/NSDictionary+Convenience.h>
#import "FFRoster.h"
#import "FFSession.h"


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
@dynamic inProgressRoster;

@dynamic fbUid;

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
                @"joinDate":        @"joined_at",
                @"inProgressRoster": @"in_progress_roster"
            }];
}

- (NSDictionary *)toNetworkRepresentation
{
    return @{ @"user": [super toNetworkRepresentation] };
}

- (void)setValuesForKeysWithNetworkDictionary:(NSDictionary *)keyedValues
{
    [super setValuesForKeysWithNetworkDictionary:keyedValues];
    
    if ([keyedValues[@"in_progress_roster"] isKindOfClass:[NSDictionary class]]) {
        [FFRoster createWithNetworkRepresentation:keyedValues[@"in_progress_roster"]
                                          session:self.session
                                          success:^(id successObj) {
                                          } failure:^(NSError *error) {
                                          }];
    }
}

- (FFRoster *)getInProgressRoster
{
    NSString *rosterId = self.inProgressRoster[@"id"];
    if (rosterId) {
        //return [[FFRoster meta] findOne:@{@"objId": rosterId}];
        return [[[[[self.session queryBuilderForClass:[FFRoster class]] property:@"objId" isEqualTo:rosterId]
                  query] results] first];
    }
    return nil;
}

@end
