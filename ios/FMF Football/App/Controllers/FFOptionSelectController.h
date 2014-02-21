//
//  FFOptionSelectController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/30/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFBaseViewController.h"

@class FFOptionSelectController;

@protocol FFOptionSelectControllerDelegate <NSObject>

@optional
- (void)optionSelectController:(FFOptionSelectController*)cont didSelectOption:(NSUInteger)idx;

@end

@interface FFOptionSelectController : FFBaseViewController

@property(nonatomic) NSString* name;
@property(nonatomic) NSArray* options;
@property(nonatomic) NSUInteger selectedOption;
@property(nonatomic, weak) id<FFOptionSelectControllerDelegate> delegate;
@property(nonatomic) NSString* sectionTitle;

@end
