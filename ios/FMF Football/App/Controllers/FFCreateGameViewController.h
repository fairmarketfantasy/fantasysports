//
//  FFCreateGameViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFBaseViewController.h"
#import "FFRoster.h"

@protocol FFCreateGameViewControllerDelegate <NSObject>

- (void)createGameControllerDidCreateGame:(FFRoster*)roster;

@end

@interface FFCreateGameViewController : FFBaseViewController

@property(nonatomic, weak) id<FFCreateGameViewControllerDelegate> delegate;

@end
