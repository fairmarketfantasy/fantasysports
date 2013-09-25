//
//  FFGameButtonView.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol FFGameButtonViewDelegate <NSObject>

- (void)gameButtonViewCreateGame;
- (void)gameButtonViewJoinGame;

@end

@interface FFGameButtonView : UIView

@property (nonatomic, weak) id<FFGameButtonViewDelegate> delegate;

@end
