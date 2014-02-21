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

- (void)rosterCellSelectPlayer:(FFRosterSlotCell*)cell;
- (void)rosterCellReplacePlayer:(FFRosterSlotCell*)cell;
- (void)rosterCellStatsForPlayer:(FFRosterSlotCell*)cell;

@end

@interface FFRosterSlotCell : UITableViewCell

@property(nonatomic, readonly) id player;
@property(nonatomic, readonly) FFRoster* roster;
@property(nonatomic, readonly) FFMarket* market;

- (void)setPlayer:(id)player andRoster:(FFRoster*)roster andMarket:(FFMarket*)market;

@property(nonatomic, weak) id<FFRosterSlotCellDelegate> delegate;

@property(nonatomic) BOOL showButtons;

@end
