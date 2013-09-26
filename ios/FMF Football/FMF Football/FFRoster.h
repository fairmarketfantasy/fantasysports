//
//  FFRoster.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <SBData/SBDataObject.h>
#import <SBData/SBTypes.h>

@interface FFRoster : SBDataObject

// rosters dont have a contest_type_id, so we have to post that separately to /rosters which then returns a roster
+ (void)createRosterWithContestTypeId:(NSInteger)cTyp success:(SBSuccessBlock)success failure:(SBErrorBlock)error;

@end
