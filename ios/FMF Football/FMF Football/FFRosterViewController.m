//
//  FFRosterViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFRosterViewController.h"
#import "FFRoster.h"
#import "FFSessionViewController.h"
#import "FFContestViewController.h"
#import <A2StoryboardSegueContext/A2StoryboardSegueContext.h>
#import "FFAlertView.h"


@interface FFRosterViewController () <UITableViewDataSource, UITableViewDelegate, SBDataObjectResultSetDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) SBDataObjectResultSet *rosters;
@property (nonatomic) SBDataObjectResultSet *historicalRosters;
@property (nonatomic) BOOL disappeared;

@end


@implementation FFRosterViewController

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
    
    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:_tableView];
    if ([self respondsToSelector:@selector(topLayoutGuide)]) {
        [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
        id topGuide = self.topLayoutGuide;
        NSDictionary *viewsDictionary = NSDictionaryOfVariableBindings(_tableView, topGuide);
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[topGuide][_tableView]|"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:viewsDictionary]];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_tableView]|"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:viewsDictionary]];
    } else {
        _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    }
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    
    UIButton *balanceView = [self.sessionController balanceView];
    [balanceView addTarget:self action:@selector(showBalance:) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:balanceView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    SBModelQuery *query = [[[[[[self.session queryBuilderForClass:[FFRoster class]]
                               property:@"ownerId" isEqualTo:self.session.user.objId]
                              property:@"state" isNotEqualTo:@"finished"]
                             orderByProperties:@[@"objId"]]
                            sort:SBModelDescending]
                           query];
    
    _rosters = [FFRoster getBulkPath:@"/rosters/mine" cacheQuery:query withSession:self.session authorized:YES];
    _rosters.clearsCollectionBeforeSaving = YES;
    _rosters.delegate = self;
    
    SBModelQuery *hQuery = [[[[[[self.session queryBuilderForClass:[FFRoster class]]
                                property:@"ownerId" isEqualTo:self.session.user.objId]
                               property:@"state" isEqualTo:@"finished"]
                              orderByProperties:@[@"objId"]]
                             sort:SBModelDescending]
                            query];
    _historicalRosters = [FFRoster getBulkPath:@"/rosters/mine?historical=y" cacheQuery:hQuery
                                   withSession:self.session authorized:YES];
    _historicalRosters.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.disappeared = NO;
    
    [self refreshLiveData];
    [_historicalRosters refresh];
    
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.disappeared = YES;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
}

- (void)showBalance:(UIButton *)seder
{
    [self performSegueWithIdentifier:@"GotoTokenPurchase" sender:nil];
}

- (void)refreshLiveData
{
    [_rosters refresh];
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        if (!self.disappeared) {
            [self refreshLiveData];
        }
    });
}

- (void)resultSetDidReload:(SBDataObjectResultSet *)resultSet
{
    if (resultSet == _rosters) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationNone];
    } else if (resultSet == _historicalRosters) {
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                      withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return [_rosters count];
    } else if (section == 1) {
        return [_historicalRosters count];
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 50;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 50)];
    header.backgroundColor = [FFStyle white];
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 290, 50)];
    lab.backgroundColor = [UIColor clearColor];
    lab.font = [FFStyle lightFont:26];
    lab.textColor = [FFStyle tableViewSectionHeaderColor];
    if (section == 0) {
        lab.text = NSLocalizedString(@"Live Contest Entries", nil);
    } else if (section == 1 && _historicalRosters.count) {
        lab.text = NSLocalizedString(@"Past Entries", nil);
    }
    [header addSubview:lab];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(295, 22.5, 10, 15)];
    disclosure.image = [UIImage imageNamed:@"disclosurelight.png"];
    disclosure.backgroundColor = [UIColor clearColor];
    [cell.contentView addSubview:disclosure];
    
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(15, CGRectGetMaxY(cell.contentView.frame), 290, 1)];
    sep.backgroundColor = [FFStyle tableViewSeparatorColor];
    sep.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [cell.contentView addSubview:sep];
    
    FFRoster *roster;
    if (indexPath.section == 0) {
        roster = [_rosters objectAtIndex:indexPath.row];
    } else if (indexPath.section == 1) {
        roster = [_historicalRosters objectAtIndex:indexPath.row];
    }
    FFContestType *cType = roster.contestType;
    
    CGFloat labw = [cType.name sizeWithFont:[FFStyle mediumFont:19]].width;
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, labw, 36)];
    lab.backgroundColor = [UIColor clearColor];
    lab.font = [FFStyle mediumFont:19];
    lab.text = cType.name;
    [cell.contentView addSubview:lab];
    
    UIImageView *status = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
    status.center = CGPointMake(CGRectGetMaxX(lab.frame)+10, CGRectGetMidY(lab.frame));
    status.backgroundColor = [UIColor clearColor];
    NSDictionary *states = @{@"in_progress": @"greydot.png",
                             @"submitted": @"greendot.png",
                             @"finished": @"bluedot.png"};
    if (states[roster.state]) {
        status.image = [UIImage imageNamed:states[roster.state]];
        [cell.contentView addSubview:status];
    }
    
    UILabel *entry = [[UILabel alloc] initWithFrame:CGRectMake(15, 32, 170, 20)];
    entry.backgroundColor = [UIColor clearColor];
    entry.font = [FFStyle regularFont:13];
    entry.textColor = [FFStyle greyTextColor];
    entry.text = [NSString stringWithFormat:@"%@ %@  %@ %@",
                  NSLocalizedString(@"Entry:", 0), cType.buyIn,
                  NSLocalizedString(@"Payout:", nil), (roster.amountPaid != nil ? roster.amountPaid : @"0")];
    [cell.contentView addSubview:entry];
    
    UILabel *rankLab = [[UILabel alloc] initWithFrame:CGRectMake(165, 5, 50, 30)];
    rankLab.backgroundColor = [UIColor clearColor];
    rankLab.font = [FFStyle regularFont:15];
    rankLab.textColor = [FFStyle darkerColorForColor:[FFStyle lightGrey]];
    rankLab.text = NSLocalizedString(@"Rank:", 0);
    [cell.contentView addSubview:rankLab];
    
    UILabel *scoreLab = [[UILabel alloc] initWithFrame:CGRectMake(165, 32, 50, 20)];
    scoreLab.backgroundColor = [UIColor clearColor];
    scoreLab.font = [FFStyle regularFont:14];
    scoreLab.text = NSLocalizedString(@"Score:", 0);
    scoreLab.textColor = [FFStyle darkerColorForColor:[FFStyle lightGrey]];
    [cell.contentView addSubview:scoreLab];
    
    UILabel *rank = [[UILabel alloc] initWithFrame:CGRectMake(210, 5, 65, 30)];
    rank.backgroundColor = [UIColor clearColor];
    rank.font = [FFStyle mediumFont:15];
    rank.textColor = [FFStyle darkGreyTextColor];
    rank.text = [NSString stringWithFormat:@"%@ %@ %@",
                 (roster.contestRank == nil ? @"0" : roster.contestRank),
                 NSLocalizedString(@"of", nil),
                 (cType.maxEntries == nil ? @"0" : cType.maxEntries)];
    [cell.contentView addSubview:rank];
    
    UILabel *score = [[UILabel alloc] initWithFrame:CGRectMake(210, 32, 65, 20)];
    score.backgroundColor = [UIColor clearColor];
    score.font = [FFStyle mediumFont:14];
    score.textColor = [FFStyle darkGreyTextColor];
    score.text = [NSString stringWithFormat:@"%@", (roster.score == nil ? @"0" : roster.score)];
    [cell.contentView addSubview:score];

    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    FFRoster *roster = [_rosters objectAtIndex:indexPath.row];
    if (!roster.market) {
        FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Loading...", nil)
                                                       messsage:nil
                                                   loadingStyle:FFAlertViewLoadingStylePlain];
        [alert showInView:self.navigationController.view];
        [FFMarket get:roster.marketId session:self.session success:^(id successObj) {
            roster.market = successObj;
            [roster save];
            [alert hide];
            [self performSegueWithIdentifier:@"GotoContest" sender:nil context:roster];
        } failure:^(NSError *error) {
            FFAlertView *ealert = [[FFAlertView alloc] initWithError:error 
                                                               title:nil
                                                   cancelButtonTitle:nil
                                                     okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                            autoHide:YES];
            [ealert showInView:self.navigationController.view];
        }];
    } else {
        [self performSegueWithIdentifier:@"GotoContest" sender:self context:roster];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"GotoContest"]) {
        FFRoster *roster = segue.context;
        ((FFContestViewController *)segue.destinationViewController).roster = roster;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
