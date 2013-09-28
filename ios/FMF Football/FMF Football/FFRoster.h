//
//  FFRoster.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <SBData/SBDataObject.h>
#import <SBData/SBTypes.h>
#import "FFContestType.h"

@interface FFRoster : SBDataObject

@property (nonatomic) SBInteger     *amountPaid;
@property (nonatomic) SBInteger     *buyIn;
@property (nonatomic) SBDate        *canceledAt;
@property (nonatomic) NSString      *canceledCause;
@property (nonatomic) NSDictionary  *contest;
@property (nonatomic) SBInteger     *contestId;
@property (nonatomic) SBInteger     *contestRank;
@property (nonatomic) SBInteger     *contestRankPayout;
//@property (nonatomic) FFContestType *contestType;
@property (nonatomic) SBInteger     *live;
@property (nonatomic) SBInteger     *marketId;
@property (nonatomic) SBDate        *nextGameTime;
@property (nonatomic) NSString      *ownerId;
@property (nonatomic) NSString      *ownerName;
@property (nonatomic) SBDate        *paidAt;
@property (nonatomic) NSArray       *players;
@property (nonatomic) NSString      *positions;
@property (nonatomic) SBFloat       *remainingSalary;
@property (nonatomic) SBInteger     *score;
@property (nonatomic) NSString      *state;

@property (nonatomic) NSString      *contestTypeId;

// rosters dont have a contest_type_id, so we have to post that separately to /rosters which then returns a roster
+ (void)createRosterWithContestTypeId:(NSInteger)cTyp
                              session:(SBSession *)sesh
                              success:(SBSuccessBlock)success
                              failure:(SBErrorBlock)failure;

- (void)addPlayer:(NSDictionary *)player success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

- (void)removePlayer:(NSDictionary *)player success:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

- (void)submitSuccess:(SBSuccessBlock)success failure:(SBErrorBlock)failure;

- (FFContestType *)contestType;

@end
