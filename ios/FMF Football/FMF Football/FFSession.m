//
//  FFSession.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFSession.h"
#import <AFNetworking/AFHTTPClient.h>
#import "FFUser.h"


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

- (void)registerAndLoginUsingFBAccessToken:(NSString *)accessToken fbUid:(NSString *)fbuid
                                   success:(SBSuccessBlock)success failure:(SBErrorBlock)failure
{
    NSDictionary *params = @{@"access_token": accessToken};
    
    NSMutableURLRequest *req = [self.anonymousHttpClient requestWithMethod:@"POST"
                                                                      path:@"/users/auth/facebook_access_token/callback"
                                                                parameters:params];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    SBJSONRequestOperation *op = [[SBJSONRequestOperation alloc] initWithRequest:req];
    
    FFUser *user = [[FFUser alloc] initWithSession:self];
    user.fbUid = fbuid;

    [op setCompletionBlockWithSuccess:^(AFHTTPRequestOperation *operation, id responseObject) {
        NSLog(@"got fb login response response %@", responseObject);
        [user setValuesForKeysWithNetworkDictionary:responseObject];
        [user save];
        self.user = user;
        [self.sessionData save];
        [self getOAuth:user fbAccessToken:accessToken success:^(id successObj) {
            self.sessionData.userKey = user.key;
            [self.sessionData save];
            success(user);
        } failure:^(NSError *error) {
            failure(error);
        }];
    } failure:^(AFHTTPRequestOperation *operation, NSError *error) {
        NSLog(@"register failed to post user operation=%@ error=%@", operation, error);
        failure(error);
    }];
    [self.anonymousHttpClient enqueueHTTPRequestOperation:op];
}

- (void)getOAuth:(FFUser *)user fbAccessToken:(NSString *)accessToken success:(SBSuccessBlock)success failure:(SBErrorBlock)err
{
    NSMutableDictionary *mutableParameters = [NSMutableDictionary dictionary];
    [mutableParameters setObject:@"facebook" forKey:@"grant_type"];
    [mutableParameters setObject:accessToken forKey:@"token"];
    [mutableParameters setObject:user.fbUid forKey:@"uid"];
    NSDictionary *parameters = [NSDictionary dictionaryWithDictionary:mutableParameters];
    
    [self.authorizedHttpClient authenticateUsingOAuthWithPath:@"/oauth2/token" parameters:parameters success:
     ^(AFOAuthCredential *credential) {
         //
         [AFOAuthCredential storeCredential:credential withIdentifier:self.identifier];
         success(user);
     } failure:^(NSError *error) {
         //
         err(error);
     }];
}

@end
