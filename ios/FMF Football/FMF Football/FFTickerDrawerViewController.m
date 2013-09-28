//
//  FFTickerDrawerViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTickerDrawerViewController.h"
#import "FFSession.h"

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
        
        self.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 48)];
        self.view.backgroundColor = [FFStyle darkGreen];
        self.view.userInteractionEnabled = YES;
        
        _collectionView = [[UICollectionView alloc] initWithFrame:CGRectMake(0, 0, 320, 48)
                                             collectionViewLayout:_flowLayout];
        [self.view addSubview:_collectionView];
        
        _errorLabel = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 300, 48)];
        _errorLabel.textColor = [FFStyle yellowErrorColor];
        _errorLabel.font = [FFStyle boldFont:16];
        _errorLabel.text = NSLocalizedString(@"Error", nil);
        _errorLabel.backgroundColor = [UIColor clearColor];
        _errorLabel.hidden = YES;
        _errorLabel.userInteractionEnabled = NO;
        [self.view insertSubview:_errorLabel belowSubview:_collectionView];
        
        _loadingLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, 0, 300, 48)];
        _loadingLabel.textColor = [FFStyle white];
        _loadingLabel.font = [FFStyle regularFont:16];
        _loadingLabel.text = NSLocalizedString(@"Loading...", nil);
        _loadingLabel.backgroundColor = [UIColor clearColor];
        _loadingLabel.hidden = YES;
        _loadingLabel.userInteractionEnabled = NO;
        [self.view insertSubview:_loadingLabel belowSubview:_collectionView];
        
        _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhite];
        _activityIndicator.frame = CGRectMake(10, 10, 10, 10);
        _activityIndicator.hidesWhenStopped = YES;
        _activityIndicator.userInteractionEnabled = NO;
        [self.view insertSubview:_activityIndicator belowSubview:_collectionView];
        [_activityIndicator stopAnimating];
        
//        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_collectionView]|"
//                                                                          options:0
//                                                                          metrics:nil
//                                                                            views:NSDictionaryOfVariableBindings(_collectionView)]];
//        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_collectionView]|"
//                                                                          options:0 metrics:nil
//                                                                            views:NSDictionaryOfVariableBindings(_collectionView)]];
        
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.delegate = self;
        _collectionView.dataSource = self;
        _collectionView.alwaysBounceHorizontal = YES;
        _collectionView.showsHorizontalScrollIndicator = NO;
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
    if (!self.tickerData || !self.tickerData.count) {
        // show loading, haven't gotten anything yet
        [self showLoading];
    }
    // not logged in yet, so use an anonymous session
    if (!self.session) {
        FFSession *tempSession = [FFSession anonymousSession];
        [tempSession anonymousJSONRequestWithMethod:@"GET" path:@"/players/public" parameters:@{} success:
         ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
             if (![JSON isKindOfClass:[NSArray class]]) {
                 [self showError:[NSError errorWithDomain:@"" code:500 userInfo:@{ }]];
                 return;
             }
             self.tickerData = JSON;
             self.lastFetch = [NSDate date];
             [self.collectionView reloadData];
             [self hideLoading];
             onSuccess(JSON);
         } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
             NSLog(@"failed to get public player timeline %@ %@", error, JSON);
             [self showError:error];
         }];
        return;
    }
    [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/mine" paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
          if (![JSON count]) {
              // there were no results from mine, so get the public one
              [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/public" paramters:@{} success:
               ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
                   if (![JSON isKindOfClass:[NSArray class]]) {
                       [self showError:[NSError errorWithDomain:@"" code:500 userInfo:@{ }]];
                       return;
                   }
                   self.tickerData = JSON;
                   self.lastFetch = [NSDate date];
                   [self.collectionView reloadData];
                   [self hideLoading];
                   onSuccess(JSON);
               } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
                   NSLog(@"failed to get ticker 2: %@ %@", error, JSON);
                   [self showError:error];
                   fail(error);
               }];
          } else {
              self.tickerData = JSON;
              self.lastFetch = [NSDate date];
              [self hideLoading];
              [self.collectionView reloadData];
              onSuccess(JSON);
          }
      } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
          NSLog(@"failed to get ticker: %@ %@", error, JSON);
          [self showError:error];
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

- (void)showLoading
{
    self.errorLabel.hidden = YES;
    self.loadingLabel.hidden = NO;
    [self.activityIndicator startAnimating];
}

- (void)hideLoading
{
    self.loadingLabel.hidden = YES;
    [self.activityIndicator stopAnimating];
}

- (void)showError:(NSError *)error
{
    NSString *errstr = nil;
    if (!(errstr = [error localizedDescription])) {
        errstr = NSLocalizedString(@"Error retrieving live stream", nil);
    }
    self.errorLabel.text = errstr;
    self.errorLabel.hidden = NO;
    self.loadingLabel.hidden = NO;
    [self.activityIndicator stopAnimating];
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
