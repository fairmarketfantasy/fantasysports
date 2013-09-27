//
//  FFPlayerSelectCell.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/26/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FFPlayerSelectCell;

@protocol FFPlayerSelectCellDelegate <NSObject>

- (void)playerSelectCellDidBuy:(FFPlayerSelectCell *)cell;

@end

@interface FFPlayerSelectCell : UITableViewCell

@property (nonatomic) NSDictionary *player;
@property (nonatomic) id<FFPlayerSelectCellDelegate> delegate;

@end
