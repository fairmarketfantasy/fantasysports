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


@interface FFContestViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;

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
    [self.view addSubview:_tableView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 2;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row == 0) {
        return 35;
    } else if (indexPath.row == 1) {
        return 150;
    }
    return 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = nil;
    
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
        [cell.contentView addSubview:sep];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
