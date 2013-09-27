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


typedef enum {
    ViewContest,
    ShowRoster,
    PickPlayer
} FFContestViewControllerState;


@interface FFContestViewController ()
<UITableViewDataSource, UITableViewDelegate,
FFRosterSlotCellDelegate, FFPlayerSelectCellDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) FFContestViewControllerState state; // current state of the FSM
@property (nonatomic) NSMutableArray *rosterPlayers; // the players in the current roster
@property (nonatomic) id currentPickPlayer;      // the current position we are picking or trading
@property (nonatomic) NSArray *availablePlayers; // shown in PickPlayer

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
    [_tableView registerClass:[FFRosterSlotCell class] forCellReuseIdentifier:@"RosterPlayer"];
    [_tableView registerClass:[FFPlayerSelectCell class] forCellReuseIdentifier:@"PlayerSelect"];
    [self.view addSubview:_tableView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (!_market || !_contest) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"showing the contest view controller but don't have a "
                                              @"contest or a market, dying now..."
                                     userInfo:@{}];
    }
    if (_roster) {
        if ([_roster.state isEqualToString:@"in_progress"]) {
            [self transitionToState:ShowRoster withContext:nil];
        }
    }
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
        return (_state == ViewContest || _state == ShowRoster) ? 3 : 2;
    } else {
        switch (_state) {
            case ShowRoster:
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
            [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
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
            } else {
                butt = [FFStyle coloredButtonWithText:NSLocalizedString(@"Cancel Entry", nil)
                                                color:[FFStyle darkGreyTextColor]
                                          borderColor:[FFStyle lightGrey]];
                [butt addTarget:self action:@selector(leaveGame:) forControlEvents:UIControlEventTouchUpInside];
            }
            butt.titleLabel.font = [FFStyle blockFont:18];
            butt.frame = CGRectMake(15, 3, 290, 38);
            [cell.contentView addSubview:butt];
        }
    } else if (indexPath.section == 1) {
        if (_state == ShowRoster) {
            id player = [_rosterPlayers objectAtIndex:indexPath.row];
            cell = [tableView dequeueReusableCellWithIdentifier:@"RosterPlayer" forIndexPath:indexPath];
            FFRosterSlotCell *r_cell = (FFRosterSlotCell *)cell;
            r_cell.player = player;
            r_cell.delegate = self;
        } else if (_state == PickPlayer) {
            cell = [tableView dequeueReusableCellWithIdentifier:@"PlayerSelect" forIndexPath:indexPath];
            FFPlayerSelectCell *s_cell = (FFPlayerSelectCell *)cell;
            s_cell.player = _availablePlayers[indexPath.row];
            s_cell.delegate = self;
        }
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
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
    
}

- (void)playerSelectCellDidBuy:(FFPlayerSelectCell *)cell
{
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Buying Player", nil)
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    __weak id weakSelf = self;
    [_roster addPlayer:cell.player success:^(id successObj) {
        [alert hide];
        [weakSelf transitionToState:ShowRoster withContext:nil];
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
        default:
            break;
    }
}

- (void)showRosterPlayers
{
    if (_state != ShowRoster) {
        NSLog(@"attempting to show roster players, but in the wrong state");
        return;
    }

    [self _reloadRosterPlayers];

    [_roster refreshInBackgroundWithBlock:^(id successObj) {
        _roster = successObj;
        
        [self _reloadRosterPlayers];
        
        [_tableView reloadSections:[NSIndexSet indexSetWithIndex:1]
                  withRowAnimation:UITableViewRowAnimationNone];
        
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [self showRosterPlayers];
        });
    } failure:^(NSError *error) {
        FFAlertView *alert = [[FFAlertView alloc] initWithError:error
                                                          title:nil
                                              cancelButtonTitle:nil
                                                okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                       autoHide:YES];
        [alert showInView:alert];
    }];
}

- (void)_reloadRosterPlayers
{
    NSArray *positions = [_roster.positions componentsSeparatedByString:@","];
    NSMutableArray *slots = [NSMutableArray arrayWithCapacity:positions.count];
    for (int i = 0; i < positions.count; i++) {
        NSString *pos = positions[i];
        NSDictionary *chosenPlayer;
        for (NSDictionary *player in _roster.players) {
            if ([player[@"position"] isEqualToString:pos]) {
                chosenPlayer = player;
                goto found_player;
            }
        }
        [slots addObject:pos]; // just the position string means the slot isn't yet filled
        continue;
    found_player:
        [slots addObject:chosenPlayer];
    }
    _rosterPlayers = slots;
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
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         FFAlertView *alert = [[FFAlertView alloc] initWithError:error
                                                           title:nil
                                               cancelButtonTitle:nil
                                                 okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                        autoHide:YES];
         [alert showInView:self.view];
     }];
}

@end
