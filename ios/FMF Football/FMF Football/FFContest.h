//
//  FFContest.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <SBData/SBDataObject.h>
#import <SBData/SBTypes.h>

@interface FFContest : SBDataObject

@property (nonatomic) SBFloat   *buyIn;
@property (nonatomic) NSString  *contestDescription;
@property (nonatomic) NSString  *iconUrl;
@property (nonatomic) NSString  *marketId;
@property (nonatomic) SBInteger *maxEntries;
@property (nonatomic) NSString  *name;
@property (nonatomic) NSString  *payoutDescription;
@property (nonatomic) NSString  *payoutStructure;
@property (nonatomic) NSInteger *isPrivate;
@property (nonatomic) SBFloat   *rake;
@property (nonatomic) NSString  *userId;

@end
