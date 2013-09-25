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
#import "FFUserBitView.h"
#import "FFGameButtonView.h"
#import "FFContest.h"
#import "FFContest2UpTabelViewCell.h"

@interface FFHomeViewController ()
<SBDataObjectResultSetDelegate, UITableViewDataSource, UITableViewDelegate,
FFMarketSelectorDelegate, FFGameButtonViewDelegate>

@property (nonatomic) SBDataObjectResultSet *markets;
@property (nonatomic) UITableView *tableView;
@property (nonatomic) FFMarketSelector *marketSelector;
@property (nonatomic) FFUserBitView *userBit;
@property (nonatomic) FFGameButtonView *gameButtonView;
@property (nonatomic) SBDataObjectResultSet *contests;

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
    [gmenu addTarget:self action:@selector(globalMenuButton:) forControlEvents:UIControlEventTouchUpInside];
    gmenu.frame = CGRectMake(-2, -2, 35, 44);
    [leftView addSubview:gmenu];
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    logo.frame = CGRectMake(32, 13, 150, 19);
    [leftView addSubview:logo];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:leftView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.sessionController.balanceView];
    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"MarketSelectorCell"];
    [_tableView registerClass:[FFContest2UpTabelViewCell class] forCellReuseIdentifier:@"ContestCell"];
    [self.view addSubview:_tableView];
    
    _marketSelector = [[FFMarketSelector alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    _marketSelector.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _marketSelector.delegate = self;
    
    _userBit = [[FFUserBitView alloc] initWithFrame:CGRectMake(0, 0, 320, 122)];
    
    _gameButtonView = [[FFGameButtonView alloc] initWithFrame:CGRectMake(0, 0, 320, 60)];
    _gameButtonView.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    UIViewController *cont2 = [[UIViewController alloc] init];
    cont2.view.backgroundColor = [UIColor redColor];
    [self showControllerInDrawer:self.sessionController.maximizedTicker
         minimizedViewController:self.sessionController.minimizedTicker
                          inView:self.view
                 resizeTableView:self.tableView
                        animated:YES];
    
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
    
    _marketSelector.markets = [_markets allObjects];
    
    _userBit.user = (FFUser *)self.session.user;
    
    [_tableView reloadData];
}

- (void)globalMenuButton:(UIButton *)button
{
    if (self.menuController) {
        [button setImage:[UIImage imageNamed:@"globalmenu.png"] forState:UIControlStateNormal];
        [self hideMenuController];
    } else {
        [button setImage:[UIImage imageNamed:@"globalmenu-highlighted.png"] forState:UIControlStateNormal];
        [self showMenuController];
    }
}

#pragma mark -
#pragma mark gamebuttonview delegate
- (void)gameButtonViewCreateGame
{
    [self performSegueWithIdentifier:@"GotoCreateGame" sender:self];
}

- (void)gameButtonViewJoinGame
{
    [self performSegueWithIdentifier:@"GotoFindGame" sender:self];
}

#pragma mark -
#pragma mark ffmarketselector delegate

- (void)didUpdateToNewMarket:(FFMarket *)market
{
    if (_contests) {
        _contests.delegate = nil;
        _contests = nil;
    }
    
    NSString *path = [NSString stringWithFormat:@"/contests/for_market/%@", market.objId];
    
    SBModelQuery *query = [[[self.session queryBuilderForClass:[FFContest class]]
                           property:@"marketId" isEqualTo:market.objId] query];
    
    _contests = [FFContest getBulkPath:path cacheQuery:query withSession:self.session authorized:YES];
    _contests.delegate = self;
    
    [_contests refresh];
}

#pragma mark -
#pragma mark uitableview delegate/datasource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return 3;
    }
    if (_contests && [_contests count]) {
        return [_contests count] / 2 + [_contests count] % 2;
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            return 122;
        } else if (indexPath.row == 2) {
            return 58;
        }
        return 44;
    }
    return 145;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell;
    if (indexPath.section == 0) {        
        cell = [tableView dequeueReusableCellWithIdentifier:@"MarketSelectorCell" forIndexPath:indexPath];
        [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
        
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(10, CGRectGetMaxY(cell.contentView.frame)-1, 300, 1)];
        sep.backgroundColor = [FFStyle tableViewSeparatorColor];
        sep.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
        
        if (indexPath.row == 0) {
            [cell.contentView addSubview:_userBit];
        } else if (indexPath.row == 1) {
            [cell.contentView addSubview:_marketSelector];
        } else if (indexPath.row == 2) {
            [cell.contentView addSubview:_gameButtonView];
        }
        [cell.contentView addSubview:sep];
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"ContestCell" forIndexPath:indexPath];
        FFContest2UpTabelViewCell *c_cell = (FFContest2UpTabelViewCell *)cell;
        NSMutableArray *contests = [NSMutableArray arrayWithObject:[_contests objectAtIndex:indexPath.row*2]];
        if ((indexPath.row * 2 + 1) != _contests.count) {
            [contests addObject:[_contests objectAtIndex:indexPath.row * 2 + 1]];
        }
        c_cell.contests = contests;
    }
    
    return cell;
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row < 3) {
        return NO;
    }
    return YES;
}

#pragma mark -
#pragma mark sbdataobjectresultset delegate

// REFRESH

- (void)resultSetDidReload:(SBDataObjectResultSet *)resultSet
{
    if (resultSet == _markets) {
        _marketSelector.markets = [resultSet allObjects];
    } else if (resultSet == _contests) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

@end
