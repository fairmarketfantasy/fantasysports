//
//  FFRoster.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFRoster.h"
#import <SBData/NSDictionary+Convenience.h>
#import "FFContestType.h"

@implementation FFRoster

@dynamic amountPaid;
@dynamic buyIn;
@dynamic canceledAt;
@dynamic canceledCause;
//@dynamic contest;
@dynamic contestId;
@dynamic contestRank;
@dynamic contestRankPayout;
//@dynamic contestType;
@dynamic live;
@dynamic marketId;
@dynamic nextGameTime;
@dynamic ownerId;
@dynamic ownerName;
@dynamic paidAt;
//@dynamic players;
@dynamic positions;
@dynamic remainingSalary;
@dynamic score;
@dynamic state;

@dynamic contestTypeId;

+ (NSString *)tableName { return @"ffroster"; }

+ (void)load { [self registerModel:self]; }

+ (NSString *)bulkPath { return @"/rosters/mine"; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{
            @"amountPaid":          @"amount_paid",
            @"buyIn":               @"buy_in",
            @"canceledAt":          @"canceled_at",
            @"canceledCause":       @"canceled_cause",
//            @"contest":             @"contest",
            @"contestId":           @"contest_id",
            @"contestRank":         @"contest_rank",
            @"contestRankPayout":   @"contest_rank_payout",
//            @"contestType":         @"contest_type",
            @"live":                @"live",
            @"marketId":            @"market_id",
            @"nextGameTime":        @"next_game_time",
            @"ownerId":             @"owner_id",
            @"ownerName":           @"owner_name",
            @"paidAt":              @"paid_at",
//            @"players":             @"players",
            @"positions":           @"positions",
            @"remainingSalary":     @"remaining_salary",
            @"score":               @"score",
            @"state":               @"state"
            }];
}

+ (NSArray *)indexes
{
    return [[super indexes] arrayByAddingObjectsFromArray:@[
            @[@"contestTypeId"]
            ]];
}

+ (void)createRosterWithContestTypeId:(NSInteger)cTyp
                              session:(SBSession *)sesh
                              success:(SBSuccessBlock)success
                              failure:(SBErrorBlock)failure
{
    NSDictionary *params = @{@"contest_type_id": [NSNumber numberWithInteger:cTyp]};
    
    [sesh authorizedJSONRequestWithMethod:@"POST" path:@"/rosters" paramters:params success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         FFRoster *roster = [[FFRoster alloc] initWithSession:sesh];
         [roster setValuesForKeysWithNetworkDictionary:JSON];
         dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
             [[self meta] inTransaction:^(SBModelMeta *meta, BOOL *rollback) {
                 [roster save];
                 success(roster);
             }];
         });
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         failure(error);
     }];
}

- (void)setValuesForKeysWithNetworkDictionary:(NSDictionary *)keyedValues
{
    [super setValuesForKeysWithNetworkDictionary:keyedValues];
    
    // save the connected contest type
    [FFContestType fromNetworkRepresentation:keyedValues[@"contest_type"] session:self.session save:YES];
}

@end
