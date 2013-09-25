//
//  FFMarket2UpTabelViewCell.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFContest.h"

@protocol FFContest2UpTableViewCellDelegate <NSObject>

- (void)didChooseContest:(FFContest *)contest;

@end

@interface FFContest2UpTabelViewCell : UITableViewCell

@property (nonatomic) NSArray *contests;
@property (nonatomic, weak) id<FFContest2UpTableViewCellDelegate> delegate;

@end
