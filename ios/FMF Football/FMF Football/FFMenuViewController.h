//
//  FFMenuViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol FFMenuViewControllerDelegate <NSObject>

- (void)performMenuSegue:(NSString *)ident;

@end

@interface FFMenuViewController : UIViewController

@property (nonatomic, weak) id<FFMenuViewControllerDelegate> delegate;

@end
