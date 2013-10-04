//
//  FFSession.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "SBSession.h"


#define FFDidReceiveRemoteNotificationAuthorization @"gotpushtoken"
#define FFDidReceiveRemoteNotification @"gotpush"


@interface FFSession : SBSession

- (void)registerAndLoginUsingFBAccessToken:(NSString *)accessToken
                                   success:(SBSuccessBlock)success
                                   failure:(SBErrorBlock)failure;

@end
