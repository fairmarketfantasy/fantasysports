//
//  FFValueEntryController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/30/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBaseViewController.h"


@protocol FFValueEntryControllerDelegate <NSObject>

- (void)valueEntryController:(id)cont didEnterValue:(NSString *)value;

@end


@interface FFValueEntryController : FFBaseViewController

@property (nonatomic) NSString *value;
@property (nonatomic) NSString *name;
@property (nonatomic, weak) id<FFValueEntryControllerDelegate> delegate;
@property (nonatomic) UIKeyboardType keyboardType;
@property (nonatomic) NSString *sectionTitle;

@end
