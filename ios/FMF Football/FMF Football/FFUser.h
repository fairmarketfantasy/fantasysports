//
//  FFUser.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "SBUser.h"

#define FF_EMAIL_REGEX @"(^[-!#$%&'*+/=?^_`{}|~0-9A-Z]+(\\.[-!#$%&'*+/=?^_`{}|~0-9A-Z]+)*|^\"([\001-\010\013\014\016-\037!#-\\[\\]-\177]|\\[\001-011\013\014\016-\177])*\")@(?:[A-Z0-9](?:[A-Z0-9-]{0,61}[A-Z0-9])?\\.)+[A-Z]{2,6}\\.?$"

@interface FFUser : SBUser

@property (nonatomic) NSNumber *balance;
@property (nonatomic) NSNumber *userId;
@property (nonatomic) NSString *name;
@property (nonatomic) NSString *imageUrl;

@end
