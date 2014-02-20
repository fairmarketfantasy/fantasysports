//
//  FFContest.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <SBData/SBDataObject.h>
#import <SBData/SBTypes.h>

@interface FFGame : SBDataObject

@property (nonatomic) NSString  *awayTeam;
@property (nonatomic) NSString  *gameDay;
@property (nonatomic) SBDate    *gameTime;
@property (nonatomic) NSString  *homeTeam;
@property (nonatomic) NSString  *network;
@property (nonatomic) NSString  *seasonType;
@property (nonatomic) SBInteger *seasonWeek;
@property (nonatomic) SBInteger *seasonYear;
@property (nonatomic) NSString  *statsId;
@property (nonatomic) NSString  *scheduled;

@end
