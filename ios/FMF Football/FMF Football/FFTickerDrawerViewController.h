//
//  FFTickerDrawerViewController.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "FFUser.h"
#import "FFDrawerViewController.h"

@interface FFTickerDrawerViewController : FFDrawerViewController
    <UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout>

@property (nonatomic) SBSession *session;

@property (nonatomic) UICollectionView *collectionView;
@property (nonatomic) UILabel *errorLabel;
@property (nonatomic) UILabel *loadingLabel;
@property (nonatomic) UIActivityIndicatorView *activityIndicator;

@property (nonatomic) NSArray *tickerData;

- (void)getTicker:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)fail;
- (BOOL)shouldUpdateTickerData;
- (void)refresh;
- (void)showLoading;
- (void)showError:(NSError *)error;

@end
