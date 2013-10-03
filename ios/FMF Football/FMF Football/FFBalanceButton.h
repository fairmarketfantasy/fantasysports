//
//  FFBalanceButton.h
//  FMF Football
//
//  Created by Samuel Sutch on 10/3/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@class FFBalanceButton;

@protocol FFBalanceViewDataSource <NSObject>

- (NSInteger)balanceViewGetBalance:(FFBalanceButton *)view;

@end


@interface FFBalanceButton : UIButton

@property (nonatomic, weak) id<FFBalanceViewDataSource> dataSource;

@end
