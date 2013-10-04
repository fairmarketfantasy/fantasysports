//
//  FFCreateGameViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/24/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFCreateGameViewController.h"
#import "FFSessionViewController.h"
#import "FFMarket.h"
#import "FFOptionSelectController.h"
#import "FFValueEntryController.h"
#import "FFRoster.h"
#import "FFAlertView.h"


#define SALARYCAP @"salarycap"
#define ENTRYFEE @"entryfee"
#define ENTRYFEE_UNDEFINED @(-1)


@interface FFCreateGameViewController ()
<UITableViewDataSource, UITableViewDelegate, SBDataObjectResultSetDelegate,
FFValueEntryControllerDelegate, FFOptionSelectControllerDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) SBDataObjectResultSet *markets;
@property (nonatomic) FFMarket *selectedMarket;
@property (nonatomic) NSArray *contestTypes;
@property (nonatomic) NSDictionary *contestTypeDesc;
@property (nonatomic) NSString *selectedContestType;
@property (nonatomic) NSUInteger selectedSalaryCap;
@property (nonatomic) NSUInteger selectedEntryFee;
@property (nonatomic) NSUInteger chosenEntryFee;

@end


@implementation FFCreateGameViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {

    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    UIButton *cancel = [FFStyle clearButtonWithText:NSLocalizedString(@"Cancel", nil) borderColor:[FFStyle white]];
    cancel.frame = CGRectMake(0, 0, 70, 30);
    [cancel addTarget:self action:@selector(cancel:) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton *create = [FFStyle clearButtonWithText:NSLocalizedString(@"Create!", nil) borderColor:[FFStyle white]];
    create.frame = CGRectMake(0, 0, 70, 30);
    [create addTarget:self action:@selector(create:) forControlEvents:UIControlEventTouchUpInside];
    
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    [logo sizeToFit];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:create];
    self.navigationItem.titleView = logo;
    
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
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.contestTypes = @[@"H2H", @"H2H RR", @"194", @"970"];
    self.contestTypeDesc = @{@"H2H":    @{SALARYCAP: @[@"$100,000"],
                                          ENTRYFEE: @[ENTRYFEE_UNDEFINED]},
                             @"H2H RR": @{SALARYCAP: @[@"$100,000"],
                                          ENTRYFEE: @[ENTRYFEE_UNDEFINED]},
                             @"194":    @{SALARYCAP: @[@"$100,000"],
                                          ENTRYFEE: @[@(0), @(1), @(10)]},
                             @"970":    @{SALARYCAP: @[@"$100,000"],
                                          ENTRYFEE: @[@(0), @(1), @(10)]}};
    
    _markets = [FFMarket getBulkWithSession:self.session authorized:YES];
    _markets.clearsCollectionBeforeSaving = YES;
    _markets.delegate = self;
    [_markets refresh];
    
    if (!_selectedContestType) {
        _selectedContestType = _contestTypes[0];
        _selectedSalaryCap = 0;
        _selectedEntryFee = 0;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.tableView reloadData];
}

/*
 NOTES:
 
 1. get markets, those are the available times
 2. h2h allows choosing an entry fee
 3. 294 and 270 allow an entry fee of free, $1 and $10
 
 data sent:
 {"market_id":142,"invitees":"","message":"","type":"h2h","buy_in":100,"salary_cap":100000}
 
 */

- (void)create:(UIButton *)sender
{
    NSDictionary *contestType = self.contestTypeDesc[_selectedContestType];
    NSNumber *buyIn;
    if ([contestType[ENTRYFEE][_selectedEntryFee] isEqual:ENTRYFEE_UNDEFINED]) {
        buyIn = @(_chosenEntryFee);
    } else {
        buyIn = contestType[ENTRYFEE][_selectedEntryFee];
    }
    
    NSDictionary *params = @{@"market_id": _selectedMarket.objId,
                             @"invitees": @"",
                             @"message": @"",
                             @"type": [_selectedContestType lowercaseString],
                             @"buy_in": buyIn,
                             @"salary_cap": @(100000)};
    
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:@"Creating Contest"
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    
    [FFRoster createWithContestDef:params session:self.session success:^(id successObj) {
        [alert hide];
        FFAlertView *salert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Contest Created", nil)
                                                         message:NSLocalizedString(@"Now invite some friends!", nil)];
        [salert showInView:self.view];
        double delayInSeconds = 2.0;
        dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
        dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
            [salert hide];
            if (self.delegate && [self.delegate respondsToSelector:@selector(createGameControllerDidCreateGame:)]) {
                [self.delegate createGameControllerDidCreateGame:successObj];
            }
        });
    } failure:^(NSError *error) {
        [alert hide];
        FFAlertView *ealert = [[FFAlertView alloc] initWithError:error
                                                           title:nil
                                               cancelButtonTitle:nil
                                                 okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                        autoHide:YES];
        [ealert showInView:self.view];
    }];
}

- (void)cancel:(UIButton *)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// result set delegate -------------------------------------------------------------------------------------------------

- (void)resultSetDidReload:(SBDataObjectResultSet *)resultSet
{
    if (!_selectedMarket && [[resultSet allObjects] count]) {
        _selectedMarket = [[resultSet allObjects] objectAtIndex:0];
        [_tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:2]]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

// table view delegate -------------------------------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return 0;
    }
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    if (section == 0) {
        return 50;
    }
    return 35;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section == 0) {
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 50)];
        header.backgroundColor = [FFStyle white];
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 290, 50)];
        lab.backgroundColor = [UIColor clearColor];
        lab.font = [FFStyle lightFont:26];
        lab.textColor = [FFStyle tableViewSectionHeaderColor];
        lab.text = NSLocalizedString(@"Create A Contest", nil);
        [header addSubview:lab];
        return header;
    } else {
        UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 35)];
        header.backgroundColor = [UIColor colorWithWhite:.9 alpha:1];
        UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
        sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
        [header addSubview:sep];
        
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 290, 35)];
        lab.font = [FFStyle regularFont:14];
        lab.backgroundColor = [UIColor clearColor];
        lab.textColor = [FFStyle darkGreyTextColor];
        if (section == 1) {
            lab.text = NSLocalizedString(@"Contest Type", nil);
        } else if (section == 2) {
            lab.text = NSLocalizedString(@"Date and Time", nil);
        } else if (section == 3) {
            lab.text = NSLocalizedString(@"Salary Cap", nil);
        } else if (section == 4) {
            lab.text = NSLocalizedString(@"Entry Fee", nil);
        }
        [header addSubview:lab];
        return header;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    if (indexPath.section == 1) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
        lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        lab.font = [FFStyle regularFont:17];
        lab.textColor = [FFStyle darkGreyTextColor];
        lab.text = _selectedContestType;
        [cell.contentView addSubview:lab];
        
        UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(295, 14.5, 10, 15)];
        disclosure.image = [UIImage imageNamed:@"disclosurelight.png"];
        disclosure.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:disclosure];
    }
    else if (indexPath.section == 2) {
        if (!_selectedMarket) {
            return cell;
        }
        // date and time market select
        UILabel *marketLabel = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 50,
                                                                         cell.contentView.frame.size.height)];
        marketLabel.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        marketLabel.font = [FFStyle regularFont:16];
        marketLabel.textColor = [FFStyle darkGreyTextColor];
        marketLabel.backgroundColor = [UIColor clearColor];
        marketLabel.textAlignment = NSTextAlignmentCenter;
        
        if (_selectedMarket.name && _selectedMarket.name.length) {
            marketLabel.text = _selectedMarket.name;
        } else {
            marketLabel.text = NSLocalizedString(@"Market", nil);
        }
        CGRect mlr = marketLabel.frame;
        mlr.size.width = [marketLabel.text sizeWithFont:marketLabel.font].width;
        marketLabel.frame = mlr;
        
        NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
        [dateFormatter setDateFormat:@"E d @ h:m a"];
        
        UILabel *timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(CGRectGetMaxX(mlr)+6, 0, 250,
                                                                       cell.contentView.frame.size.height)];
        timeLabel.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        timeLabel.font = [FFStyle mediumFont:16];
        timeLabel.textColor = [FFStyle black];
        timeLabel.textAlignment = NSTextAlignmentCenter;
        timeLabel.backgroundColor = [UIColor clearColor];
        timeLabel.text = [dateFormatter stringFromDate:_selectedMarket.startedAt];
        
        CGRect tlr = timeLabel.frame;
        tlr.size.width = [timeLabel.text sizeWithFont:timeLabel.font].width;
        timeLabel.frame = tlr;
        
        [cell.contentView addSubview:timeLabel];
        [cell.contentView addSubview:marketLabel];
        
        UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(295, 14.5, 10, 15)];
        disclosure.image = [UIImage imageNamed:@"disclosurelight.png"];
        disclosure.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:disclosure];
    }
    else if (indexPath.section == 3) {
        // salary cap
        NSDictionary *contestType = _contestTypeDesc[_selectedContestType];
        
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
        lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        lab.font = [FFStyle regularFont:17];
        lab.textColor = [FFStyle darkGreyTextColor];
        lab.text = contestType[SALARYCAP][_selectedSalaryCap];
        [cell.contentView addSubview:lab];
        
        if ([contestType[SALARYCAP] count] > 1) {
            UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(295, 14.5, 10, 15)];
            disclosure.image = [UIImage imageNamed:@"disclosurelight.png"];
            disclosure.backgroundColor = [UIColor clearColor];
            [cell.contentView addSubview:disclosure];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    else if (indexPath.section == 4) {
        // entry fee
        NSDictionary *contestType = _contestTypeDesc[_selectedContestType];
        
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
        lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        lab.font = [FFStyle regularFont:17];
        lab.textColor = [FFStyle darkGreyTextColor];
        
        if ([contestType[ENTRYFEE][_selectedEntryFee] isEqual:ENTRYFEE_UNDEFINED]) {
            lab.text = [NSString stringWithFormat:@"%d %@", _chosenEntryFee, NSLocalizedString(@"Tokens", nil)];
        } else {
            lab.text = [NSString stringWithFormat:@"%@ %@",
                        contestType[ENTRYFEE][_selectedEntryFee], NSLocalizedString(@"Tokens", nil)];
        }
        [cell.contentView addSubview:lab];
        
        if ([contestType[ENTRYFEE] count] > 1 || [contestType[ENTRYFEE][_selectedSalaryCap] isEqual:ENTRYFEE_UNDEFINED]) {
            UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(295, 14.5, 10, 15)];
            disclosure.image = [UIImage imageNamed:@"disclosurelight.png"];
            disclosure.backgroundColor = [UIColor clearColor];
            [cell.contentView addSubview:disclosure];
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
        } else {
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1) {
        // go to contest type selection
        [self performSegueWithIdentifier:@"GotoContestTypeSelect" sender:self];
    }
    else if (indexPath.section == 2) {
        if (!_selectedMarket) {
            return;
        }
        // go to date and time market select
        [self performSegueWithIdentifier:@"GotoMarketSelect" sender:self];
    }
    else if (indexPath.section == 3) {
        // salary cap
        NSDictionary *contestType = _contestTypeDesc[_selectedContestType];
        
        if ([contestType[SALARYCAP] count] > 1) {
            // goto salary cap
            [self performSegueWithIdentifier:@"GotoSalaryCapSelect" sender:self];
        }
    }
    else if (indexPath.section == 4) {
        // entry fee
        NSDictionary *contestType = _contestTypeDesc[_selectedContestType];
        
        if ([contestType[ENTRYFEE][_selectedSalaryCap] isEqual:ENTRYFEE_UNDEFINED]) {
            // goto value entry
            [self performSegueWithIdentifier:@"GotoEntryFeeEntry" sender:self];
        } else {
            // go to entry fee select
            [self performSegueWithIdentifier:@"GotoEntryFeeSelect" sender:self];
        }
    }
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"GotoContestTypeSelect"]) {
        FFOptionSelectController *c = segue.destinationViewController;
        c.options = self.contestTypes;
        c.selectedOption = [self.contestTypes indexOfObject:_selectedContestType];
        c.name = segue.identifier;
        c.delegate = self;
        c.sectionTitle = NSLocalizedString(@"Choose Contest Type", nil);
    }
    else if ([segue.identifier isEqualToString:@"GotoMarketSelect"]) {
        FFOptionSelectController *c = segue.destinationViewController;
        NSUInteger sel = [[_markets allObjects] indexOfObject:_selectedMarket];
        NSMutableArray *opts = [NSMutableArray array];
        for (FFMarket *market in [_markets allObjects]) {
            NSString *mkt;
            if (market.name && market.name.length) {
                mkt = market.name;
            } else {
                mkt = NSLocalizedString(@"Market", nil);
            }
            
            NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
            [dateFormatter setDateFormat:@"E d @ h:m a"];
            
            [opts addObject:[NSString stringWithFormat:@"%@ - %@", mkt,
                             [dateFormatter stringFromDate:market.startedAt]]];
        }
        c.options = opts;
        c.selectedOption = sel;
        c.delegate = self;
        c.name = segue.identifier;
        c.sectionTitle = NSLocalizedString(@"Choose Market", nil);
    }
    else if ([segue.identifier isEqualToString:@"GotoSalaryCapSelect"]) {
        // we dont handle this yet
    }
    else if ([segue.identifier isEqualToString:@"GotoEntryFeeSelect"]) {
        FFOptionSelectController *c = segue.destinationViewController;
        NSMutableArray *opts = [NSMutableArray array];
        for (NSNumber *n in _contestTypeDesc[_selectedContestType][ENTRYFEE]) {
            [opts addObject:[NSString stringWithFormat:@"%@ %@", n, NSLocalizedString(@"Tokens", nil)]];
        }
        c.options = opts;
        c.selectedOption = _selectedEntryFee;
        c.name = segue.identifier;
        c.delegate = self;
        c.sectionTitle = NSLocalizedString(@"Choose Entry Fee", nil);
    }
    else if ([segue.identifier isEqualToString:@"GotoEntryFeeEntry"]) {
        FFValueEntryController *c = segue.destinationViewController;
        c.keyboardType = UIKeyboardTypeDecimalPad;
        c.value = [NSString stringWithFormat:@"%d", _chosenEntryFee];
        c.name = segue.identifier;
        c.delegate = self;
        c.sectionTitle = NSLocalizedString(@"Set Entry Fee", nil);
    }
}

- (void)optionSelectController:(FFOptionSelectController *)cont didSelectOption:(NSUInteger)idx
{
    if ([cont.name isEqualToString:@"GotoContestTypeSelect"]) {
        if (![_contestTypes[idx] isEqualToString:_selectedContestType]) {
            // they chose a new option
            _selectedContestType = _contestTypes[idx];
            _selectedEntryFee = 0;
            _selectedSalaryCap = 0;
            _chosenEntryFee = 0;
            [self.tableView reloadData];
        }
    }
    else if ([cont.name isEqualToString:@"GotoMarketSelect"]) {
        _selectedMarket = _markets.allObjects[idx];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    else if ([cont.name isEqualToString:@"GotoEntryFeeSelect"]) {
        _selectedEntryFee = idx;
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:4]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self.navigationController popToViewController:self animated:YES];
}

- (void)valueEntryController:(FFValueEntryController *)cont didEnterValue:(NSString *)value
{
    if ([cont.name isEqualToString:@"GotoEntryFeeEntry"]) {
        _chosenEntryFee = [value integerValue];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:4]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    [self.navigationController popToViewController:self animated:YES];
}

@end
