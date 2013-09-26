//
//  FFContestViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFContestViewController.h"
#import <FormatterKit/TTTOrdinalNumberFormatter.h>
#import "FFContestView.h"
#import <QuartzCore/QuartzCore.h>
#import "FFRoster.h"

typedef enum {
    ViewContest,
    ChoosePlayers,
    PickPlayer,
    UnstartedGame,
    StartedGame
} FFContestViewControllerState;

@interface FFContestViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) FFContestViewControllerState state;
@property (nonatomic) NSArray *players;

- (void)transitionToState:(FFContestViewControllerState)newState withContext:(id)ctx;

@end


@implementation FFContestViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width,
                                                               self.view.frame.size.height)];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.delegate = self;
    _tableView.dataSource = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"BannerCell"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ContestCell"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"EnterCell"];
    [self.view addSubview:_tableView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1 + (_state != ViewContest ? 1 : 0);
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return _state == ViewContest ? 3 : 2;
    } else {
        return _players != nil ? [_players count] : 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == 0) {
        return 35;
    } else if (indexPath.row == 1) {
        return 150;
    } else if (indexPath.row == 2) {
        return 44;
    }
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"BannerCell" forIndexPath:indexPath];
            cell.contentView.backgroundColor = [UIColor colorWithWhite:.95 alpha:1];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
            cell.textLabel.font = [FFStyle regularFont:14];
            cell.textLabel.textColor = [FFStyle darkGreyTextColor];
            cell.textLabel.backgroundColor = cell.contentView.backgroundColor;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.adjustsFontSizeToFitWidth = YES;
            cell.textLabel.adjustsLetterSpacingToFitWidth = YES;
            
            TTTOrdinalNumberFormatter *ordinalNumberFormatter = [[TTTOrdinalNumberFormatter alloc] init];
            [ordinalNumberFormatter setLocale:[NSLocale currentLocale]];
            [ordinalNumberFormatter setGrammaticalGender:TTTOrdinalNumberFormatterMaleGender];
            
            NSDateFormatter *mformatter = [[NSDateFormatter alloc] init];
            mformatter.dateFormat = @"eeee MMMM";
            
            NSDateFormatter *tformatter = [[NSDateFormatter alloc] init];
            [tformatter setLocale:[NSLocale currentLocale]];
            [tformatter setTimeZone:[NSTimeZone systemTimeZone]];
            tformatter.dateFormat = @"ha";
            
            NSDateComponents *components = [[NSCalendar currentCalendar] components:
                                            NSDayCalendarUnit | NSMonthCalendarUnit | NSYearCalendarUnit
                                                                           fromDate:_market.startedAt];
            
            NSString *str = [NSString stringWithFormat:@"%@ %@ %@ at %@",
                             NSLocalizedString(@"Game starts", nil),
                             [mformatter stringFromDate:_market.startedAt],
                             [ordinalNumberFormatter stringFromNumber:@(components.day)],
                             [tformatter stringFromDate:_market.startedAt]];
            cell.textLabel.text = str;
            
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(cell.contentView.frame)-1,
                                                                   cell.contentView.frame.size.width, 1)];
            sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
            [cell.contentView addSubview:sep];
        }
        else if (indexPath.row == 1) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"ContestCell" forIndexPath:indexPath];
            FFContestView *view = [[FFContestView alloc] initWithFrame:CGRectMake(0, 0, 320, 150)];
            view.market = _market;
            view.contest = _contest;
            [cell.contentView addSubview:view];
            
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(cell.contentView.frame)-1,
                                                                   cell.contentView.frame.size.width, 1)];
            sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
        }
        else if (indexPath.row == 2) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"EnterCell"];
            NSString *txt;
            if (_contest.buyIn.integerValue < 1) {
                txt = [NSString stringWithFormat:@"%@ %@ %@",
                       NSLocalizedString(@"Enter", nil),
                       _contest.name,
                       NSLocalizedString(@"For Free!", nil)];
            } else {
                txt = [NSString stringWithFormat:@"%@ %@ with %@ %@",
                             NSLocalizedString(@"Enter", nil),
                             _contest.name,
                             [_contest.buyIn description],
                             NSLocalizedString(@"Tokens", nil)];
            }
            FFCustomButton *butt = [FFStyle coloredButtonWithText:txt
                                                            color:[FFStyle brightOrange]
                                                      borderColor:[FFStyle brightOrange]];
            [butt addTarget:self action:@selector(enterGame:) forControlEvents:UIControlEventTouchUpInside];
            butt.titleLabel.font = [FFStyle blockFont:18];
            butt.frame = CGRectMake(15, 3, 290, 38);
            [cell.contentView addSubview:butt];
        }
    } else if (indexPath.section == 1) {
        if (_state == ChoosePlayers) {
            
        }
    }
    
    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 1) {
        return 40;
    }
    return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section == 1) {
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 40)];
        header.backgroundColor = [UIColor colorWithWhite:.9 alpha:1];
        
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
        [header addSubview:sep];
        
        sep = [[UIView alloc] initWithFrame:CGRectMake(0, 38, 320, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
        [header addSubview:sep];
        
        sep = [[UIView alloc] initWithFrame:CGRectMake(0, 39, 320, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:1 alpha:.5];
        [header addSubview:sep];
        
        UILabel *price = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 305, 38)];
        price.backgroundColor = [UIColor clearColor];
        price.textColor = [FFStyle brightGreen];
        price.font = [FFStyle blockFont:26];
        price.textAlignment = NSTextAlignmentRight;
        price.text = @"$100,000";
        [header addSubview:price];
        
        if (_state == ChoosePlayers) {
            UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, 40)];
            lab.font = [FFStyle lightFont:26];
            lab.backgroundColor = [UIColor clearColor];
            lab.textColor = [UIColor colorWithWhite:.15 alpha:1];
            lab.text = NSLocalizedString(@"Pick Your Team", nil);
            [header addSubview:lab];
        }
        return header;
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)enterGame:(UIButton *)button
{
    [self transitionToState:ChoosePlayers withContext:nil];
}

- (void)transitionToState:(FFContestViewControllerState)newState withContext:(id)ctx
{
    FFContestViewControllerState previousState = _state;
    _state = newState;
    switch (_state) {
        case ChoosePlayers:
            if (previousState == ViewContest) {
                [self.tableView beginUpdates];
                [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:1]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView endUpdates];
            } else {
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            break;
        default:
            break;
    }
}

@end
