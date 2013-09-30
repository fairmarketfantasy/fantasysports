//
//  FFOptionSelectController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/30/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFOptionSelectController.h"


@interface FFOptionSelectController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) UITableView *tableView;

@end


@implementation FFOptionSelectController

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

    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width,
                                                                   self.view.frame.size.height)
                                                  style:UITableViewStylePlain];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    [self.view addSubview:_tableView];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    [_tableView reloadData];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

// table view delegate -------------------------------------------------------------------------------------------------

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.options.count;
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
    lab.text = self.sectionTitle;
    [header addSubview:lab];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
    lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    lab.font = [FFStyle regularFont:17];
    lab.textColor = [FFStyle darkGreyTextColor];
    lab.text = _options[indexPath.row];
    [cell.contentView addSubview:lab];
    
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
    [cell.contentView addSubview:sep];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
