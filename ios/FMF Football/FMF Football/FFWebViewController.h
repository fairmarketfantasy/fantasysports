//
//  FFWebViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 10/3/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>



@interface FFWebViewController : UIViewController

@property (nonatomic) NSURL *URL;
@property (strong, nonatomic) NSArray *activityItems;
@property (strong, nonatomic) NSArray *applicationActivities;
@property (strong, nonatomic) NSArray *excludedActivityTypes;

- (void)load;

@end
