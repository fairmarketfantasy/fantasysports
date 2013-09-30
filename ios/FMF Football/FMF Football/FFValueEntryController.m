//
//  FFValueEntryController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/30/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFValueEntryController.h"
#import "FFTextField.h"


@interface FFValueEntryController () <UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate>

@property (nonatomic) UITableView *tableView;

@end


@implementation FFValueEntryController

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
    return 1;
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
    
    UITextField *field = [[FFTextField alloc] initWithFrame:CGRectMake(15, 4, 290, 38)];
    field.borderStyle = UITextBorderStyleNone;
    field.font = [FFStyle regularFont:17];
    field.textColor = [FFStyle darkGreyTextColor];
    field.delegate = self;
    field.keyboardType = self.keyboardType;
    [cell.contentView addSubview:field];
    
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:.8 alpha:1];
    [cell.contentView addSubview:sep];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView willDisplayCell:(UITableViewCell *)cell forRowAtIndexPath:(NSIndexPath *)indexPath
{
    [cell.contentView.subviews[0] becomeFirstResponder];
}

@end
