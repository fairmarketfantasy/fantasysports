//
//  FFRoster.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFRoster.h"
#import <SBData/NSDictionary+Convenience.h>

@implementation FFRoster

+ (NSString *)tableName { return @"ffroster"; }

+ (void)load { [self registerModel:self]; }

+ (NSString *)bulkPath { return @"/rosters"; }

+ (NSDictionary *)propertyToNetworkKeyMapping
{
    return [[super propertyToNetworkKeyMapping] dictionaryByMergingWithDictionary:@{

            }];
}

+ (NSArray *)indexes
{
    return [[super indexes] arrayByAddingObjectsFromArray:@[]];
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

@end
