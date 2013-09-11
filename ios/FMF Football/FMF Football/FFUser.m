//
//  FFUser.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFUser.h"

@implementation FFUser

+ (NSString *)tableName { return @"ff-user"; }

+ (void)load { [self registerModel:self]; }

@end
