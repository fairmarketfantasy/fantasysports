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
#import "FFSessionViewController.h"
#import "FFAlertView.h"
#import "FFRosterSlotCell.h"
#import "FFPlayerSelectCell.h"
#import "FFContestEntrantsViewController.h"
#import "FFInviteViewController.h"


typedef enum {
    NoState,
    ViewContest,
    ShowRoster,
    PickPlayer,
    ContestEntered
} FFContestViewControllerState;


@interface FFContestViewController ()
<UITableViewDataSource, UITableViewDelegate,
FFRosterSlotCellDelegate, FFPlayerSelectCellDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) FFContestViewControllerState state; // current state of the FSM
@property (nonatomic) NSMutableArray *rosterPlayers; // the players in the current roster
@property (nonatomic) id currentPickPlayer;      // the current position we are picking or trading
@property (nonatomic) NSArray *availablePlayers; // shown in PickPlayer
@property (nonatomic) UIView *submitButtonView;
@property (nonatomic) UILabel *remainingSalaryLabel;
@property (nonatomic) UILabel *numEntrantsLabel;

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
//    _tableView.separatorColor = [UIColor clearColor];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"BannerCell"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"ContestCell"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"EnterCell"];
    [_tableView registerClass:[FFRosterSlotCell class] forCellReuseIdentifier:@"RosterPlayer"];
    [_tableView registerClass:[FFPlayerSelectCell class] forCellReuseIdentifier:@"PlayerSelect"];
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"EntrantsCell"];
    [self.view addSubview:_tableView];
    
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:
                                              self.sessionController.balanceView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

- (void)viewWillAppear:(BOOL)animated
{
    if (!_market || !_contest) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"showing the contest view controller but don't have a "
                @"contest or a market, dying now..."
                                     userInfo:@{}];
    }
    if (_roster) {
        if ([_roster.state isEqualToString:@"in_progress"]) {
            [self transitionToState:ShowRoster withContext:nil];
        } else if ([_roster.state isEqualToString:@"submitted"]) {
            [self transitionToState:ContestEntered withContext:nil];
        }
    }
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [self transitionToState:NoState withContext:nil];
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
        int rows = 2;
        if (_state == ViewContest || _state == ShowRoster || _state == ContestEntered) {
            rows++;
        }
        if (_state == ContestEntered) {
            rows++;
        }
        return rows;
    } else {
        switch (_state) {
            case ShowRoster:
            case ContestEntered:
                return _rosterPlayers != nil ? _rosterPlayers.count : 0;
            case PickPlayer:
                return _availablePlayers != nil ? _availablePlayers.count : 0;
            default:
                return 0;
        }
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            return 35;
        } else if (indexPath.row == 1) {
            return 150;
        } else if (indexPath.row == 2) {
            return 52;
        } else if (indexPath.row == 3) {
            return 44;
        }
    }
    return 80;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
    if (indexPath.section == 0) {
        if (indexPath.row == 0) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"BannerCell" forIndexPath:indexPath];
            [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
            if ([_roster.live integerValue]) {
                cell.contentView.backgroundColor = [FFStyle brightGreen];
                cell.textLabel.font = [FFStyle regularFont:18];
                cell.textLabel.textColor = [FFStyle white];
                cell.textLabel.backgroundColor = cell.contentView.backgroundColor;
                cell.textLabel.textAlignment = NSTextAlignmentCenter;
                cell.textLabel.text = NSLocalizedString(@"Game has started!", nil);
            } else {
                cell.contentView.backgroundColor = [UIColor colorWithWhite:.95 alpha:1];
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
            }
            
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(cell.contentView.frame),
                                                                   cell.contentView.frame.size.width, 1)];
            sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
            [cell.contentView addSubview:sep];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        else if (indexPath.row == 1) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"ContestCell" forIndexPath:indexPath];
            [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
            FFContestView *view = [[FFContestView alloc] initWithFrame:CGRectMake(0, 0, 320, 150)];
            view.market = _market;
            view.contest = _contest;
            [cell.contentView addSubview:view];
            
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
        else if (indexPath.row == 2) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"EnterCell"];
            [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
            FFCustomButton *butt;
            if (_state == ViewContest) {
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
                butt = [FFStyle coloredButtonWithText:txt
                                                color:[FFStyle brightOrange]
                                          borderColor:[FFStyle brightOrange]];
                [butt addTarget:self action:@selector(enterGame:) forControlEvents:UIControlEventTouchUpInside];
            } else if (_state == ShowRoster) {
                butt = [FFStyle coloredButtonWithText:NSLocalizedString(@"Cancel Entry", nil)
                                                color:[FFStyle darkGreyTextColor]
                                          borderColor:[FFStyle lightGrey]];
                [butt addTarget:self action:@selector(leaveGame:) forControlEvents:UIControlEventTouchUpInside];
            } else if (_state == ContestEntered) {
                butt = [FFStyle coloredButtonWithText:NSLocalizedString(@"Invite Friends", nil)
                                                color:[FFStyle brightOrange]
                                          borderColor:[FFStyle brightOrange]];
                [butt addTarget:self action:@selector(inviteToGame:) forControlEvents:UIControlEventTouchUpInside];
            }
            butt.titleLabel.font = [FFStyle blockFont:18];
            butt.frame = CGRectMake(15, 3, 290, 38);
            [cell.contentView addSubview:butt];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else if (indexPath.row == 3) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"EntrantsCell" forIndexPath:indexPath];
            [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
            
            UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(295, 14.5, 10, 15)];
            disclosure.image = [UIImage imageNamed:@"disclosurelight.png"];
            disclosure.backgroundColor = [UIColor clearColor];
            [cell.contentView addSubview:disclosure];
            
            UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 250, 44)];
            lab.backgroundColor = [UIColor clearColor];
            lab.font = [FFStyle regularFont:17];
            lab.textColor = [FFStyle greyTextColor];
            NSString *text = [NSString stringWithFormat:@"%@ %@",
                              _roster.contest[@"num_rosters"], NSLocalizedString(@"Contest Entrants", nil)];
            lab.text = text;
            [cell.contentView addSubview:lab];
            
            _numEntrantsLabel = cell.textLabel;
            
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0,
                                                                   cell.contentView.frame.size.width, 1)];
            sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
            [cell.contentView addSubview:sep];
        }
    } else if (indexPath.section == 1) {
        if (_state == ShowRoster || _state == ContestEntered) {
            id player = [_rosterPlayers objectAtIndex:indexPath.row];
            cell = [tableView dequeueReusableCellWithIdentifier:@"RosterPlayer" forIndexPath:indexPath];
            FFRosterSlotCell *r_cell = (FFRosterSlotCell *)cell;
            r_cell.player = player;
            r_cell.market = _market;
            r_cell.roster = _roster;
            r_cell.delegate = self;
        } else if (_state == PickPlayer) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"PlayerSelect" forIndexPath:indexPath];
            FFPlayerSelectCell *s_cell = (FFPlayerSelectCell *)cell;
            s_cell.player = _availablePlayers[indexPath.row];
            s_cell.delegate = self;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    if (!cell) {
        NSLog(@"fart");
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
        price.text = [NSString stringWithFormat:@"$%d", [[_roster.remainingSalary description] integerValue]];
        _remainingSalaryLabel = price;
        [header addSubview:price];
        
        if (_state == ShowRoster) {
            UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, 40)];
            lab.font = [FFStyle lightFont:26];
            lab.backgroundColor = [UIColor clearColor];
            lab.textColor = [UIColor colorWithWhite:.15 alpha:1];
            lab.text = NSLocalizedString(@"Pick Your Team", nil);
            [header addSubview:lab];
        } else if (_state == PickPlayer) {
            UIButton *back = [UIButton buttonWithType:UIButtonTypeCustom];
            back.frame = CGRectMake(5, 0, 40, 40);
            [back setBackgroundImage:[UIImage imageNamed:@"sectionback.png"] forState:UIControlStateNormal];
            [back addTarget:self action:@selector(backFromPlayerSelect:) forControlEvents:UIControlEventTouchUpInside];
            [header addSubview:back];
            
            NSString *pos;
            if ([_currentPickPlayer isKindOfClass:[NSString class]]) {
                pos = _currentPickPlayer;
            } else {
                pos = _currentPickPlayer[@"position"];
            }
            NSDictionary *names = @{@"QB":  NSLocalizedString(@"Quarterback", nil),
                                    @"RB":  NSLocalizedString(@"Running Back", nil),
                                    @"WR":  NSLocalizedString(@"Wide Receiver", nil),
                                    @"DEF": NSLocalizedString(@"Defense", nil),
                                    @"K":   NSLocalizedString(@"Kicker", nil),
                                    @"TE":  NSLocalizedString(@"Tight End", nil)};
            
            UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(45, 0, 320, 40)];
            lab.font = [FFStyle lightFont:26];
            lab.backgroundColor = [UIColor clearColor];
            lab.textColor = [UIColor colorWithWhite:.15 alpha:1];
            lab.text = names[pos];
            [header addSubview:lab];
        } else if (_state == ContestEntered) {
            UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, 40)];
            lab.font = [FFStyle lightFont:26];
            lab.backgroundColor = [UIColor clearColor];
            lab.textColor = [UIColor colorWithWhite:.15 alpha:1];
            lab.text = NSLocalizedString(@"My Team", nil);
            [header addSubview:lab];
        }
        return header;
    }
    return nil;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (_state == ContestEntered && indexPath.row == 3) {
        [self performSegueWithIdentifier:@"GotoContestEntrants" sender:nil];
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"GotoContestEntrants"]) {
        ((FFContestEntrantsViewController *)segue.destinationViewController).contest = _roster.contest;
    }
    if ([segue.identifier isEqualToString:@"GotoInvite"]) {
        ((FFInviteViewController *)segue.destinationViewController).roster = _roster;
    }
}

- (void)enterGame:(UIButton *)button
{
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Starting Roster", nil)
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    [FFRoster createRosterWithContestTypeId:[_contest.objId integerValue]
                                    session:self.session success:
     ^(id successObj) {
         [alert hide];
         _roster = successObj;
         [self transitionToState:ShowRoster withContext:nil];
     } failure:^(NSError *error) {
         [alert hide];
         FFAlertView *alert = [[FFAlertView alloc] initWithError:error
                                                           title:nil
                                               cancelButtonTitle:nil
                                                 okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                        autoHide:YES];
         [alert showInView:self.view];
     }];
}

- (void)leaveGame:(UIButton *)button
{
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Loading", nil)
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    [_roster removeInBackgroundWithBlock:^(id successObj) {
        [alert hide];
        [self transitionToState:ViewContest withContext:nil];
    } failure:^(NSError *error) {
        [alert hide];
        FFAlertView *eAlert = [[FFAlertView alloc] initWithError:error
                                                           title:nil
                                               cancelButtonTitle:nil
                                                 okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                        autoHide:YES];
        [eAlert showInView:self.view];
    }];
}

- (void)inviteToGame:(UIButton *)button
{
    [self performSegueWithIdentifier:@"GotoInvite" sender:nil];
}

- (void)backFromPlayerSelect:(UIButton *)button
{
    [self transitionToState:ShowRoster withContext:nil];
}

- (void)rosterCellSelectPlayer:(FFRosterSlotCell *)cell
{
    [self transitionToState:PickPlayer withContext:cell.player];
}

- (void)rosterCellReplacePlayer:(FFRosterSlotCell *)cell
{
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:@"Removing Player"
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    [_roster removePlayer:cell.player success:^(id successObj) {
        [alert hide];
        cell.player = cell.player[@"position"];
    } failure:^(NSError *error) {
        [alert hide];
        FFAlertView *eAlert = [[FFAlertView alloc] initWithError:error
                                                           title:nil
                                               cancelButtonTitle:nil
                                                 okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                        autoHide:YES];
        [eAlert showInView:self.view];
    }];
}

- (void)playerSelectCellDidBuy:(FFPlayerSelectCell *)cell
{
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Buying Player", nil)
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    FFContestViewController *weakSelf = self;
    [_roster addPlayer:cell.player success:^(id successObj) {
        [alert hide];
        FFContestViewControllerState next;
        if ([weakSelf->_roster.state isEqualToString:@"submitted"]) {
            next = ContestEntered;
        } else {
            next = ShowRoster;
        }
        [weakSelf transitionToState:next withContext:nil];
    } failure:^(NSError *error) {
        [alert hide];
        FFAlertView *eAlert = [[FFAlertView alloc] initWithError:error
                                                          title:nil
                                              cancelButtonTitle:nil
                                                okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                       autoHide:YES];
        [eAlert showInView:[weakSelf view]];
    }];
}

- (void)rosterCellStatsForPlayer:(FFRosterSlotCell *)cell
{
    
}

- (void)submitRoster:(UIButton *)sender
{
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Submitting", nil)
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    [_roster submitSuccess:^(id successObj) {
        [alert hide];
        _roster = successObj;
        [self transitionToState:ContestEntered withContext:nil];
    } failure:^(NSError *error) {
        [alert hide];
        FFAlertView *eAlert = [[FFAlertView alloc] initWithError:error
                                                           title:nil
                                               cancelButtonTitle:nil
                                                 okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                        autoHide:YES];
        [eAlert showInView:self.view];
    }];
}

- (void)transitionToState:(FFContestViewControllerState)newState withContext:(id)ctx
{
    if (newState == _state) {
        NSLog(@"tried to transition to the current state... ignoring");
        return;
    }
    FFContestViewControllerState previousState = _state;
    _state = newState;
    switch (_state) {
        case ViewContest:
            [self hideSubmitRosterBanner];
            [self.tableView beginUpdates];
            [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView deleteSections:[NSIndexSet indexSetWithIndex:1]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView endUpdates];
            break;
        case ShowRoster:
            [self.tableView beginUpdates];
            if (previousState == ViewContest) {
                [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertSections:[NSIndexSet indexSetWithIndex:1]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
            } else if (previousState == PickPlayer) {
                [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
            }
            [self showRosterPlayers];
            [self.tableView endUpdates];
            break;
        case PickPlayer:
            _currentPickPlayer = ctx;
            [self showPlayersForPosition:[ctx isKindOfClass:[NSString class]] ? ctx : ctx[@"position"]];
            [self.tableView beginUpdates];
            [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]]
                                  withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
            [self.tableView endUpdates];
            break;
        case ContestEntered:
            [self showRosterPlayers];
            if (previousState == NoState) {
                [self.tableView reloadData];
            } else {
                [self.tableView beginUpdates];
                [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:2 inSection:0]]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:3 inSection:0]]
                                      withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
                [self.tableView endUpdates];
            }
            if (previousState == ShowRoster) {
                [self hideSubmitRosterBanner];
            }
            break;
        default:
            break;
    }
}

- (void)showRosterPlayers
{
    if (!(_state == ShowRoster || _state == ContestEntered)) {
        NSLog(@"attempting to show roster players, but in the wrong state");
        return;
    }

    [self _reloadRosterPlayers];

    [_roster refreshInBackgroundWithBlock:^(id successObj) {
        if (!(_state == ShowRoster || _state == ContestEntered)) {
            return;
        }
        _roster = successObj;
        
        [self _reloadRosterPlayers];
        
        NSMutableArray *paths = [NSMutableArray arrayWithCapacity:_rosterPlayers.count];
        for (int i = 0; i < _rosterPlayers.count; i++) {
            [paths addObject:[NSIndexPath indexPathForRow:i inSection:1]];
        }
        [_tableView reloadRowsAtIndexPaths:paths withRowAnimation:UITableViewRowAnimationNone];
        
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            // only poll if we're viewing this screen
            [self showRosterPlayers];
        });
    } failure:^(NSError *error) {
        if (_state == ViewContest || _state == PickPlayer) {
            return ;
        }
        FFAlertView *alert = [[FFAlertView alloc] initWithError:error
                                                          title:nil
                                              cancelButtonTitle:nil
                                                okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                       autoHide:YES];
        [alert showInView:self.view];
    }];
}

- (void)_reloadRosterPlayers
{
    NSArray *positions = [_roster.positions componentsSeparatedByString:@","];
    NSMutableArray *slots = [NSMutableArray arrayWithCapacity:positions.count];
    NSMutableSet *alreadyAssigned = [NSMutableSet set]; // keep who is already assigned to which position
    int numMissing = 0;
    for (int i = 0; i < positions.count; i++) {
        NSString *pos = positions[i];
        NSDictionary *chosenPlayer;
        for (NSDictionary *player in _roster.players) {
            if ([player[@"position"] isEqualToString:pos] && ![alreadyAssigned containsObject:player[@"id"]]) {
                chosenPlayer = player;
                [alreadyAssigned addObject:player[@"id"]];
                goto found_player;
            }
        }
        numMissing++;
        [slots addObject:pos]; // just the position string means the slot isn't yet filled
        continue;
    found_player:
        [slots addObject:chosenPlayer];
    }
    _rosterPlayers = slots;
    
    if (_remainingSalaryLabel) {
        _remainingSalaryLabel.text = [NSString stringWithFormat:@"$%d",
                                      [[_roster.remainingSalary description] integerValue]];
    }
    
    if (_numEntrantsLabel) {
        _numEntrantsLabel.text = [NSString stringWithFormat:@"%@ %@",
                                  _roster.contest[@"num_rosters"],
                                  NSLocalizedString(@"Contest Entrants", nil)];
    }
    
    if (numMissing == 0) {
        [self showSubmitRosterBanner];
    } else {
        [self hideSubmitRosterBanner];
    }
}

- (void)showPlayersForPosition:(NSString *)pos
{
    if (_state != PickPlayer) {
        NSLog(@"attempting to show players but in the wrong state");
        return;
    }
    NSDictionary *params = @{@"position": pos, @"roster_id": _roster.objId};
    [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/" paramters:params success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         if (_state != PickPlayer) {
             return;
         }
         _availablePlayers = JSON;
         [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                       withRowAnimation:UITableViewRowAnimationAutomatic];
         
         __strong FFContestViewController *strongSelf = self;
         
         double delayInSeconds = 2.0;
         dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
         dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
             NSString *lastPos = ((strongSelf->_currentPickPlayer
                                   && [strongSelf->_currentPickPlayer isKindOfClass:[NSDictionary class]])
                                  ? strongSelf->_currentPickPlayer[@"position"]
                                  : strongSelf->_currentPickPlayer);
             // only poll again if we are still picking a player and picking the correct one
             if (strongSelf->_state == PickPlayer && [pos isEqualToString:lastPos]) {
                 [strongSelf showPlayersForPosition:lastPos];
             }
         });
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         if (_state != PickPlayer) {
             return;
         }
         FFAlertView *alert = [[FFAlertView alloc] initWithError:error
                                                           title:nil
                                               cancelButtonTitle:nil
                                                 okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                        autoHide:YES];
         [alert showInView:self.view];
     }];
}

- (void)showSubmitRosterBanner
{
    if (_state != ShowRoster) {
        return;
    }
    if (!_submitButtonView) {
        UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(self.view.frame),
                                                                self.view.frame.size.width, 80)];
        view.backgroundColor = [UIColor colorWithWhite:.25 alpha:1];
        
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, view.frame.size.width, 30)];
        lab.backgroundColor = view.backgroundColor;
        lab.font = [FFStyle regularFont:14];
        lab.textColor = [UIColor colorWithWhite:.95 alpha:1];
        lab.textAlignment = NSTextAlignmentCenter;
        lab.text = NSLocalizedString(@"All slots are filled!", nil);
        [view addSubview:lab];
        
        UIButton *butt = [FFStyle coloredButtonWithText:NSLocalizedString(@"Submit Roster!", nil)
                                                  color:[FFStyle brightOrange]
                                            borderColor:[FFStyle brightOrange]];
        butt.frame = CGRectMake(15, 30, 290, 38);
        butt.titleLabel.font = [FFStyle blockFont:18];
        [butt addTarget:self action:@selector(submitRoster:) forControlEvents:UIControlEventTouchUpInside];
        [view addSubview:butt];
        
        _submitButtonView = view;
        [self.view addSubview:view];
        
        [UIView animateWithDuration:.25 animations:^{
            view.frame = CGRectOffset(view.frame, 0, -view.frame.size.height);
            _tableView.contentInset = UIEdgeInsetsMake(0, 0, view.frame.size.height, 0);
        }];
    }
}

- (void)hideSubmitRosterBanner
{
    if (_submitButtonView) {
        UIView *view = _submitButtonView;
        _submitButtonView = nil;
        [UIView animateWithDuration:.25 animations:^{
            view.frame = CGRectOffset(view.frame, 0, view.frame.size.height);
            _tableView.contentInset = UIEdgeInsetsZero;
        } completion:^(BOOL finished) {
            if (finished) {
                [view removeFromSuperview];
            }
        }];
    }
}

@end