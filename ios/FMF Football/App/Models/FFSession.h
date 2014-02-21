//
//  FFSession.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <SBSession.h>

#define FFDidReceiveRemoteNotificationAuthorization @"gotpushtoken"
#define FFDidReceiveRemoteNotification @"gotpush"

@interface FFSession : SBSession

@property(nonatomic) SBUser* user;
@property(nonatomic) SBSessionData* sessionData;

- (void)registerAndLoginUsingFBAccessToken:(NSString*)accessToken
                                     fbUid:(NSString*)fbUid
                                   success:(SBSuccessBlock)success
                                   failure:(SBErrorBlock)failure;
- (void)clearCredentials;

@end
