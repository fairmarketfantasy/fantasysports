//
//  FFContestEntrantsViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/27/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFContestEntrantsViewController.h"
#import <SBData/SBDataObject.h>
#import "FFRoster.h"
#import "FFSessionViewController.h"


@interface FFContestEntrantsViewController ()
<UITableViewDataSource, UITableViewDelegate, SBDataObjectResultSetDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) SBDataObjectResultSet *rosters;
@property (nonatomic) BOOL disappeared;

@end


@implementation FFContestEntrantsViewController

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
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width,
                                                               self.view.frame.size.height)];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_tableView];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:
                                              self.sessionController.balanceView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    NSString *path = [NSString stringWithFormat:@"/rosters/in_contest/%@", _contest[@"id"]];
    SBModelQuery *query = [[[[[self.session queryBuilderForClass:[FFRoster class]]
                              property:@"contestId" isEqualTo:_contest[@"id"]]
                             orderByProperties:@[@"contestRank"]]
                            sort:SBModelAscending]
                           query];
    _rosters = [FFRoster getBulkPath:path cacheQuery:query withSession:self.session authorized:YES];
    _rosters.clearsCollectionBeforeSaving = YES;
    _rosters.delegate = self;
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.disappeared = NO;
    [self refreshLiveData];
    
    [self.tableView reloadData];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    self.disappeared = YES;
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
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
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
    lab.text = NSLocalizedString(@"Contest Entrants", nil);
    [header addSubview:lab];
    return header;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_rosters count];
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
    
    FFRoster *roster = [_rosters objectAtIndex:indexPath.row];
//    FFContestType *cType = roster.contestType;
    
    NSString *tit = [NSString stringWithFormat:@"#%@ %@", roster.contestRank,
                     (roster.ownerName != nil && roster.ownerName.length
                      ? roster.ownerName
                      : NSLocalizedString(@"Entrant", nil))];
    
    CGFloat labw = [tit sizeWithFont:[FFStyle mediumFont:19]].width;
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, labw, 60)];
    lab.backgroundColor = [UIColor clearColor];
    lab.font = [FFStyle mediumFont:19];
    lab.text = tit;
    [cell.contentView addSubview:lab];
    
//    UILabel *entry = [[UILabel alloc] initWithFrame:CGRectMake(15, 32, 170, 20)];
//    entry.backgroundColor = [UIColor clearColor];
//    entry.font = [FFStyle regularFont:13];
//    entry.textColor = [FFStyle greyTextColor];
//    entry.text = [NSString stringWithFormat:@"%@ %@",
//                  NSLocalizedString(@"Entrant:", 0), roster.ownerName];
//    [cell.contentView addSubview:entry];
    
    UILabel *rankLab = [[UILabel alloc] initWithFrame:CGRectMake(160, 5, 50, 30)];
    rankLab.backgroundColor = [UIColor clearColor];
    rankLab.font = [FFStyle regularFont:15];
    rankLab.textColor = [FFStyle darkerColorForColor:[FFStyle lightGrey]];
    rankLab.text = NSLocalizedString(@"Score:", 0);
    [cell.contentView addSubview:rankLab];
    
    UILabel *scoreLab = [[UILabel alloc] initWithFrame:CGRectMake(160, 32, 50, 20)];
    scoreLab.backgroundColor = [UIColor clearColor];
    scoreLab.font = [FFStyle regularFont:14];
    scoreLab.text = NSLocalizedString(@"Payout:", 0);
    scoreLab.textColor = [FFStyle darkerColorForColor:[FFStyle lightGrey]];
    [cell.contentView addSubview:scoreLab];
    
    UILabel *rank = [[UILabel alloc] initWithFrame:CGRectMake(210, 5, 65, 30)];
    rank.backgroundColor = [UIColor clearColor];
    rank.font = [FFStyle mediumFont:15];
    rank.textColor = [FFStyle darkGreyTextColor];
    rank.text = [NSString stringWithFormat:@"%@ %@", roster.score, NSLocalizedString(@"points", nil)];
    [cell.contentView addSubview:rank];
    
    UILabel *score = [[UILabel alloc] initWithFrame:CGRectMake(210, 32, 65, 20)];
    score.backgroundColor = [UIColor clearColor];
    score.font = [FFStyle mediumFont:14];
    score.textColor = [FFStyle darkGreyTextColor];
    score.text = [NSString stringWithFormat:@"%@", (roster.amountPaid != nil ? roster.amountPaid : @"0")];
    [cell.contentView addSubview:score];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    FFRoster *roster = [_rosters objectAtIndex:indexPath.row];
    [self performSegueWithIdentifier:@"GotoContest" sender:self context:roster];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
