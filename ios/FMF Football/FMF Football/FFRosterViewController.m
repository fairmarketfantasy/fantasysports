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


@interface FFRosterViewController () <UITableViewDataSource, UITableViewDelegate, SBDataObjectResultSetDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) SBDataObjectResultSet *rosters;

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
    
    _tableView = [[UITableView alloc] initWithFrame:self.view.frame];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_tableView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    _rosters = [FFRoster getBulkPath:@"/rosters/mine" withSession:self.session authorized:YES];
    _rosters.delegate = self;
    
    [_rosters refresh];
    
    [self.tableView reloadData];
}

- (void)resultSetDidReload:(SBDataObjectResultSet *)resultSet
{
    [self.tableView reloadData];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [_rosters count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    cell.textLabel.text = [[_rosters objectAtIndex:indexPath.row] description];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    FFRoster *roster = [_rosters objectAtIndex:indexPath.row];
    [self performSegueWithIdentifier:@"GotoContest" sender:self context:roster];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"GotoContest"]) {
        FFRoster *roster = segue.context;
        FFContestType *contest = [[[[[self.session queryBuilderForClass:[FFContestType class]]
                                     property:@"contestTypeId" isEqualTo:roster.contestTypeId]
                                    query] results] first];
        FFMarket *market = [[[[[self.session queryBuilderForClass:[FFMarket class]]
                               property:@"objId" isEqualTo:contest.marketId]
                              query] results] first];
        ((FFContestViewController *)segue.destinationViewController).roster = roster;
        ((FFContestViewController *)segue.destinationViewController).contest = contest;
        ((FFContestViewController *)segue.destinationViewController).market = market;
    }
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
