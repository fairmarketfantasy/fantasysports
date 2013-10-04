//
//  FFSession.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFSession.h"
#import <AFNetworking/AFHTTPClient.h>


@implementation FFSession

- (id)deserializeJSON:(id)JSON
{
    if (JSON[@"data"] && [JSON[@"data"] isKindOfClass:[NSArray class]]) {
        // it's JSONH
        NSArray *lst = JSON[@"data"];
        if (!lst.count) {
            return [NSArray array];
        }
        NSMutableArray *ret = [NSMutableArray array];
        int klength = [lst[0] integerValue];
        int i = 1 + klength;
        while (i < lst.count) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            int ki = 0;
            while (ki < klength) {
                ki++;
                d[lst[ki]] = lst[i];
                i++;
            }
            [ret addObject:d];
        }
        return ret;
    }
    return JSON;
}

- (void)registerAndLoginUsingFBAccessToken:(NSString *)accessToken
                                   success:(SBSuccessBlock)success
                                   failure:(SBErrorBlock)failure
{
    NSDictionary *params = @{@"access_token": accessToken};
    
    NSMutableURLRequest *req = [self.anonymousHttpClient requestWithMethod:@"POST"
                                                                      path:@"/auth/facebook_access_token/callback"
                                                                parameters:params];
    SBJSONRequestOperation *op = [[SBJSONRequestOperation alloc] initWithRequest:req];
    
    //    [op setAuthenticationAgainstProtectionSpaceBlock:^BOOL(NSURLConnection *connection, NSURLProtectionSpace *protectionSpace) {
    //        return YES;
    //    }];
    //
    //    [op setAuthenticationChallengeBlock:^(NSURLConnection *connection, NSURLAuthenticationChallenge *challenge) {
    //        if ([challenge.protectionSpace.authenticationMethod isEqualToString:NSURLAuthenticationMethodServerTrust]) {
    //            [challenge.sender useCredential:[NSURLCredential credentialForTrust:challenge.protectionSpace.serverTrust] forAuthenticationChallenge:challenge];
    //        }
    //    }];
    
    [op setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"successfully registered user - now attempting to get oauth");
//        [user setValuesForKeysWithNetworkDictionary:responseObject];
//        [user save];
//        self.user = user;
//        [self.sessionData save]; // make sure we have an identifier
//        [self getOAuth:user password:password success:^ (id _) {
//            self.sessionData.userKey = [user key];
//            [self.sessionData save];
//            [self syncPushToken];
//            success(user);
//        } failure:failure];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"register failed to post user operation=%@ error=%@", operation, error);
        failure(error);
    }];
    [self.anonymousHttpClient enqueueHTTPRequestOperation:op];
}

@end
