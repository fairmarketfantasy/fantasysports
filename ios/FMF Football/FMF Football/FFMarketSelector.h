//
//  FFMarketSelector.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFMarket.h"

@protocol FFMarketSelectorDelegate <NSObject>

- (void)didUpdateToNewMarket:(FFMarket*)market;

@end

@interface FFMarketSelector : UIView

@property(nonatomic) NSArray* markets;
@property(nonatomic) FFMarket* selectedMarket;
@property(nonatomic, weak) id<FFMarketSelectorDelegate> delegate;

@end
