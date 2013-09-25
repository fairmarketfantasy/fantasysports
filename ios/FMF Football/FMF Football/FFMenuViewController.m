//
//  FFMenuViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/25/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFMenuViewController.h"

@interface FFMenuViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;

@end

@implementation FFMenuViewController

- (id)init
{
    self = [super init];
    if (self) {
        self.view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 504)];
        self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:.9];
        
        _tableView = [[UITableView alloc] initWithFrame:self.view.frame];
        _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        _tableView.backgroundColor = [UIColor clearColor];
        _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
        _tableView.dataSource = self;
        _tableView.delegate = self;
        [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
        [self.view addSubview:_tableView];
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 6;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    switch (indexPath.row) {
        case 0:
            cell.textLabel.text = NSLocalizedString(@"My Games", nil);
            break;
        case 1:
            cell.textLabel.text = NSLocalizedString(@"Create Game", nil);
            break;
        case 2:
            cell.textLabel.text = NSLocalizedString(@"Join Game", nil);
            break;
        case 3:
            cell.textLabel.text = NSLocalizedString(@"My Account", nil);
            break;
        case 4:
            cell.textLabel.text = NSLocalizedString(@"Terms & Conditions", nil);
            break;
        case 5:
            cell.textLabel.text = NSLocalizedString(@"Sign Out", nil);
            break;
        default:
            break;
    }
    cell.textLabel.textColor = [FFStyle lightGrey];
    cell.textLabel.font = [FFStyle regularFont:17];
    
    // add disclosure indicator
    UIImageView *disc = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 10, 15)];
    disc.backgroundColor = [UIColor clearColor];
    disc.image = [UIImage imageNamed:@"disclosuredark.png"];
    cell.accessoryView = disc;
    
    // add separator to bottom
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(cell.contentView.frame),
                                                           cell.contentView.frame.size.width, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:1 alpha:.1];
    [cell.contentView addSubview:sep];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    switch (indexPath.row) {
        case 0:
            break;
        case 1:
            break;
        case 2:
            break;
        case 3:
            break;
        case 4:
            break;
        case 5:
            break;
        default:
            break;
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
