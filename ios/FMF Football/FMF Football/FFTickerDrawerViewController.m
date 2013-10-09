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

@property (nonatomic) UICollectionViewFlowLayout *flowLayout;
@property (nonatomic) NSDate *dontTickUntil; // you can block the ticker for a period of time
@property (nonatomic) BOOL doTick;
@property (nonatomic) NSUInteger currentTickItem;

@end


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
        
        _collectionView.backgroundColor = [UIColor clearColor];
        _collectionView.delegate = self;
        _collectionView.dataSource = self;
        _collectionView.alwaysBounceHorizontal = YES;
        _collectionView.showsHorizontalScrollIndicator = NO;
        
        _currentTickItem = 0;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (self.tickerData) {
        [self.collectionView reloadData];
    } else {
        [self tickerShowLoading:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    _doTick = YES;
    [self tick];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    _doTick = NO;
}

- (void)tick
{
    if (!_doTick) {
        return;
    }
    double delayInSeconds = 2.5;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        // don't scroll if we were recently scrolling or something
        if (self.dontTickUntil) {
            NSDate *now = [NSDate date];
            if ([now compare:self.dontTickUntil] == NSOrderedAscending) {
                NSLog(@"ignoring ticker tick");
                return [self tick];
            } else {
                self.dontTickUntil = nil;
                // we just scrolled, so set tickernext to the first visible cell
                _currentTickItem = [(NSIndexPath *)[self.collectionView indexPathsForVisibleItems][0] item];
            }
        }
        // scroll to the next one if available
        NSLog(@"ticker ticking");
        NSArray *visible = [self.collectionView indexPathsForVisibleItems];
        if (visible.count > 1) {
            NSIndexPath *next = [NSIndexPath indexPathForItem:_currentTickItem inSection:0];
            if (next.item < self.tickerData.count) {
                [self.collectionView scrollToItemAtIndexPath:next
                                            atScrollPosition:UICollectionViewScrollPositionLeft
                                                    animated:YES];
            }
        }
        _currentTickItem++;
        [self tick];
    });
}

// ticker data source delegate -----------------------------------------------------------------------------------------

- (void)tickerShowLoading:(FFTickerDataSource *)source
{
    self.errorLabel.hidden = YES;
    self.collectionView.hidden = YES;
    
    self.loadingLabel.hidden = NO;
    [self.activityIndicator startAnimating];
}

- (void)ticker:(FFTickerDataSource *)ticker showError:(NSString *)errStr
{
    self.loadingLabel.hidden = YES;
    [self.activityIndicator stopAnimating];
    self.collectionView.hidden = YES;
    
    self.errorLabel.hidden = NO;
    if (!errStr) {
        errStr = NSLocalizedString(@"Error retrieving live stream", nil);
    }
    self.errorLabel.text = errStr;
}

- (void)tickerGotData:(FFTickerDataSource *)ticker
{
    self.loadingLabel.hidden = YES;
    [self.activityIndicator stopAnimating];
    self.errorLabel.hidden = YES;
    
    self.collectionView.hidden = NO;
    [self.collectionView reloadData];
    self.tickerData = [ticker.tickerData copy];
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

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    self.dontTickUntil = [NSDate dateWithTimeIntervalSinceNow:5];
}

@end
