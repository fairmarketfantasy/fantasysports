//
//  FFUser.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "SBUser.h"


#define FF_EMAIL_REGEX @"(^[-!#$%&'*+/=?^_`{}|~0-9A-Z]+(\\.[-!#$%&'*+/=?^_`{}|~0-9A-Z]+)*|^\"([\001-\010\013\014\016-\037!#-\\[\\]-\177]|\\[\001-011\013\014\016-\177])*\")@(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\\.)+[A-Z]{2,6}\\.?$"


@class FFRoster;


@interface FFUser : SBUser

@property (nonatomic) SBFloat       *balance;
@property (nonatomic) SBFloat       *winPercentile;
@property (nonatomic) SBDate        *joinDate;
@property (nonatomic) NSString      *name;
@property (nonatomic) NSString      *imageUrl;
@property (nonatomic) SBInteger     *tokenBalance;
@property (nonatomic) NSString      *email;
@property (nonatomic) SBInteger     *totalPoints;
@property (nonatomic) SBInteger     *totalWins;
@property (nonatomic) NSDictionary  *inProgressRoster;

@property (nonatomic) NSString      *fbUid;

- (FFRoster *)getInProgressRoster;

@end
