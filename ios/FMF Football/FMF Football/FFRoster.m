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
#import <objc/runtime.h>
#import <dispatch/dispatch.h>


@interface FFRoster ()

@property (nonatomic) FFContestType *_contestType;

@end


@implementation FFRoster

@dynamic amountPaid;
@dynamic buyIn;
@dynamic canceledAt;
@dynamic canceledCause;
@dynamic contest;
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
@dynamic players;
@dynamic positions;
@dynamic remainingSalary;
@dynamic score;
@dynamic state;

@dynamic contestTypeId;

+ (NSString *)tableName { return @"ffroster"; }

+ (void)load { [self registerModel:self]; }

+ (NSString *)bulkPath { return @"/rosters"; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{
            @"amountPaid":          @"amount_paid",
            @"buyIn":               @"buy_in",
            @"canceledAt":          @"canceled_at",
            @"canceledCause":       @"canceled_cause",
            @"contest":             @"contest",
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
            @"players":             @"players",
            @"positions":           @"positions",
            @"remainingSalary":     @"remaining_salary",
            @"score":               @"score",
            @"state":               @"state"
            }];
}

+ (NSArray *)indexes
{
    return [[super indexes] arrayByAddingObjectsFromArray:@[
            @[@"userKey", @"contestTypeId"],
            @[@"userKey", @"contestId"],
            @[@"userKey", @"ownerId", @"state"],
            @[@"contestRank"], // for sorting
            @[@"objId"] // also for sorting
            ]];
}

+ (void)createRosterWithContestTypeId:(NSInteger)cTyp
                              session:(SBSession *)sesh
                              success:(SBSuccessBlock)success
                              failure:(SBErrorBlock)failure
{
    NSDictionary *params = @{@"contest_type_id": [NSNumber numberWithInteger:cTyp]};
    
    [sesh authorizedJSONRequestWithMethod:@"POST" path:[self bulkPath] paramters:params success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         [self createWithNetworkRepresentation:JSON session:sesh success:success failure:failure];
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         failure(error);
     }];
}

- (void)addPlayer:(NSDictionary *)player success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSString *path = [[self path] stringByAppendingFormat:@"/add_player/%@", player[@"id"]];
    [self.session authorizedJSONRequestWithMethod:@"POST" path:path  paramters:nil success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         success(JSON);
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         failure(error);
     }];
}

- (void)removePlayer:(NSDictionary *)player success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSString *path = [[self path] stringByAppendingFormat:@"/remove_player/%@", player[@"id"]];
    [self.session authorizedJSONRequestWithMethod:@"POST" path:path paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         success(JSON);
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         failure(error);
     }];
}

- (void)submitSuccess:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSString *path = [[self path] stringByAppendingString:@"/submit"];
    [self.session authorizedJSONRequestWithMethod:@"POST" path:path paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         [self updateWithNetworkRepresentation:JSON success:success failure:failure];
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         failure(error);
     }];
}

- (void)setValuesForKeysWithNetworkDictionary:(NSDictionary *)keyedValues
{
    [super setValuesForKeysWithNetworkDictionary:keyedValues];
    
    self.contestTypeId = keyedValues[@"contest_type"][@"id"];
    
    // save the connected contest type
    [FFContestType fromNetworkRepresentation:keyedValues[@"contest_type"] session:self.session save:YES];
}

- (FFContestType *)contestType
{
    if (!__contestType) {
        __contestType = [[[[[self.session queryBuilderForClass:[FFContestType class]]
                            property:@"objId" isEqualTo:self.contestTypeId]
                           query] results] first];
    }
    return __contestType;
}

@end
