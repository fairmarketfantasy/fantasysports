//
//  FFRosterSlotCell.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/26/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFRoster.h"
#import "FFMarket.h"

@class FFRosterSlotCell;

@protocol FFRosterSlotCellDelegate <NSObject>

- (void)rosterCellSelectPlayer:(FFRosterSlotCell *)cell;
- (void)rosterCellReplacePlayer:(FFRosterSlotCell *)cell;
- (void)rosterCellStatsForPlayer:(FFRosterSlotCell *)cell;

@end

@interface FFRosterSlotCell : UITableViewCell

@property (nonatomic) id player;
@property (nonatomic) FFRoster *roster;
@property (nonatomic) FFMarket *market;
@property (nonatomic, weak) id<FFRosterSlotCellDelegate> delegate;

@end
