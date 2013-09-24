//
//  FFHomeViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/17/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFHomeViewController.h"
#import "FFSessionViewController.h"
#import "FFMarket.h"
#import "FFMarketSelector.h"

@interface FFHomeViewController () <SBDataObjectResultSetDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) SBDataObjectResultSet *markets;
@property (nonatomic) UITableView *tableView;
@property (nonatomic) FFMarketSelector *marketSelector;

@end

@implementation FFHomeViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    UIView *leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    UIButton *gmenu = [UIButton buttonWithType:UIButtonTypeCustom];
    [gmenu setImage:[UIImage imageNamed:@"globalmenu.png"] forState:UIControlStateNormal];
    gmenu.frame = CGRectMake(-2, 0, 35, 44);
    [leftView addSubview:gmenu];
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    logo.frame = CGRectMake(32, 15, 150, 19);
    [leftView addSubview:logo];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:leftView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.sessionController.balanceView];
    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"MarketSelectorCell"];
    [self.view addSubview:_tableView];
    
    _marketSelector = [[FFMarketSelector alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    _marketSelector.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    UIViewController *cont2 = [[UIViewController alloc] init];
    cont2.view.backgroundColor = [UIColor redColor];
    [self showControllerInDrawer:self.sessionController.maximizedTicker
         minimizedViewController:self.sessionController.minimizedTicker
                        animated:NO];
    
    // uncomment to test the banner
//    double delayInSeconds = 2.0;
//    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
//    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
//        [self showBanner:@"Hello there" target:nil selector:NULL animated:YES];
//
//    });
    
    _markets = [FFMarket getBulkWithSession:self.session authorized:YES];
    _markets.delegate = self;
    [_markets refresh];
    
    [_tableView reloadData];
}

#pragma mark -
#pragma mark uitableview delegate/datasource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"MarketSelectorCell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    _marketSelector.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [cell.contentView addSubview:_marketSelector];

    return cell;
}

#pragma mark -
#pragma mark sbdataobjectresultset delegate

// REFRESH

- (void)resultSetWillReload:(SBDataObjectResultSet *)resultSet
{
    
}

- (void)resultSetDidReload:(SBDataObjectResultSet *)resultSet
{
//    [self.refreshControl endRefreshing];
//    _fetchedDate = [NSDate date];
//    NSString *lastUpdated = [_fetchedDate description];
//    self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:
//                                           [NSString stringWithFormat:NSLocalizedString(@"Last Updated %@", nil), lastUpdated]];
//    [self.session setPreferenceValue:lastUpdated forKey:@"LAST_INBOX_UPDATE"];
    if (resultSet == _markets) {
        _marketSelector.markets = [resultSet allObjects];
    }
}

- (void)resultSet:(SBDataObjectResultSet *)resultSet didFailToReload:(NSError *)error
{
//    self.refreshControl.attributedTitle = [[NSAttributedString alloc] initWithString:NSLocalizedString(@"Failed To Refresh", nil)];
//    CTAlertView *alert = [[CTAlertView alloc] initWithError:error title:nil cancelButtonTitle:@"Dismiss" okayButtonTitle:nil autoHide:YES];
//    alert.onCancel = ^ (id _) {
//        [self.refreshControl endRefreshing];
//    };
//    [alert showInView:self.parentViewController.view];
}

// LOAD MORE

- (void)resultSetWillLoadMore:(SBDataObjectResultSet *)resultSet
{
//    _loadingMore = YES;
}

- (void)resultSetDidLoadMore:(SBDataObjectResultSet *)resultSet
{
//    _loadingMore = NO;
}

- (void)resultSet:(SBDataObjectResultSet *)resultSet didFailToLoadMore:(NSError *)error
{
//    _loadingMore = NO;
    //CTAlertView *alert = [[CTAlertView alloc] initWithError:error title:nil cancelButtonTitle:@"Dismiss" okayButtonTitle:nil autoHide:YES];
    //[alert showInView:self.parentViewController.view];
}

// UPDATES

- (void)resultSetWillBeginUpdating:(SBDataObjectResultSet *)resultSet
{
//    [self.tableView beginUpdates];
}

- (void)resultSet:(SBDataObjectResultSet *)resultSet didInsertObjectAtIndexes:(NSIndexSet *)indexes
{
//    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:indexes.count];
//    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
//        [paths addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
//    }];
//    [self.tableView insertRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
}

- (void)resultSet:(SBDataObjectResultSet *)resultSet didRemoveObjectAtIndexes:(NSIndexSet *)indexes
{
//    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:indexes.count];
//    [indexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
//        [paths addObject:[NSIndexPath indexPathForRow:idx inSection:0]];
//    }];
//    [self.tableView deleteRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
}

- (void)resultSetWillEndUpdating:(SBDataObjectResultSet *)resultSet
{
//    [self.tableView endUpdates];
}

@end
