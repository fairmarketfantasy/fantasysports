//
//  FFTickerDrawerViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTickerDrawerViewController.h"

@interface FFTickerDrawerViewController ()

@property (nonatomic) NSDate *lastFetch;
@property (nonatomic) UICollectionViewFlowLayout *flowLayout;

@end

#define TICKER_UPDATE_FREQUENCY_IN_SECONDS 60

@implementation FFTickerDrawerViewController

- (id)init
{
    self = [super init];
    if (self) {
        _flowLayout = [[UICollectionViewFlowLayout alloc] init];
        _flowLayout.scrollDirection = UICollectionViewScrollDirectionHorizontal;
        
        self.view = self.collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 0, 0)
                                                             collectionViewLayout:_flowLayout];
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.delegate = self;
        _collectionView.dataSource = self;
        _collectionView.alwaysBounceHorizontal = YES;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)refresh
{
    [self.collectionView reloadData];
}

- (void)getTicker:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)fail
{
    [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/mine" paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
          if (![JSON[@"data"] count]) {
              // there were no results from mine, so get the public one
              [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/public" paramters:@{} success:
               ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
                   self.tickerData = JSON;
                   self.lastFetch = [NSDate date];
                   [self.collectionView reloadData];
                   onSuccess(JSON);
               } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
                   NSLog(@"failed to get ticker 2: %@ %@", error, JSON);
                   fail(error);
               }];
          } else {
              self.tickerData = JSON;
              self.lastFetch = [NSDate date];
              [self.collectionView reloadData];
              onSuccess(JSON);
          }
      } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
          NSLog(@"failed to get ticker: %@ %@", error, JSON);
          fail(error);
      }];
}

- (BOOL)shouldUpdateTickerData
{
    if (!self.lastFetch) {
        return YES; // hasn't yet been fetched
    }
    NSDate *expires = [NSDate dateWithTimeIntervalSinceNow:TICKER_UPDATE_FREQUENCY_IN_SECONDS];
    if ([expires compare:self.lastFetch] == NSOrderedDescending) {
        return NO;
    }
    return YES;
}

// collection view data source -----------------------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInCollectionView:(UICollectionView *)collectionView
{
    return 1;
}

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.tickerData.count;
}

- (CGSize)collectionView:(UICollectionView *)collectionView
                  layout:(UICollectionViewLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"thism ethod must be implemented in a subclass"
                                 userInfo:nil];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                   reason:@"this method must be implemented in a subclass"
                                 userInfo:nil];
}

@end
