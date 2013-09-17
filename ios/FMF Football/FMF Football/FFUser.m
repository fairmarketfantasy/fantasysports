//
//  FFUser.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFUser.h"

@implementation FFUser

+ (NSString *)tableName { return @"ffuser"; }

+ (void)load { [self registerModel:self]; }

- (NSString *)listPath { return @"/users.json"; }

- (NSString *)detailPathSpec { return @"/users.json"; }

// customize the to the nonstandard way the /users endpoint works
- (AFHTTPClientParameterEncoding)paramterEncoding { return AFFormURLParameterEncoding; }

- (NSDictionary *)toNetworkRepresentation
{
    return @{ @"user": [super toNetworkRepresentation] };
}

@end
