//
//  FFOptionSelectController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/30/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFOptionSelectController.h"

@interface FFOptionSelectController () <UITableViewDataSource, UITableViewDelegate>

@property(nonatomic) UITableView* tableView;

@end

@implementation FFOptionSelectController

- (id)initWithNibName:(NSString*)nibNameOrNil bundle:(NSBundle*)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil
                           bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _tableView = [[UITableView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:_tableView];
    if ([self respondsToSelector:@selector(topLayoutGuide)]) {
        [_tableView setTranslatesAutoresizingMaskIntoConstraints:NO];
        id topGuide = self.topLayoutGuide;
        NSDictionary* viewsDictionary = NSDictionaryOfVariableBindings(_tableView, topGuide);
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
    [_tableView registerClass:[UITableViewCell class]
        forCellReuseIdentifier:@"Cell"];
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

- (NSInteger)numberOfSectionsInTableView:(UITableView*)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.options.count;
}

- (CGFloat)tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 50;
}

- (UIView*)tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section
{
    UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 50)];
    header.backgroundColor = [FFStyle white];
    UILabel* lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 290, 50)];
    lab.backgroundColor = [UIColor clearColor];
    lab.font = [FFStyle lightFont:26];
    lab.textColor = [FFStyle tableViewSectionHeaderColor];
    lab.text = self.sectionTitle;
    [header addSubview:lab];
    return header;
}

- (UITableViewCell*)tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"
                                                            forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    UILabel* lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
    lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    lab.font = [FFStyle regularFont:17];
    lab.textColor = [FFStyle darkGreyTextColor];
    lab.text = [_options[indexPath.row] description];
    [cell.contentView addSubview:lab];

    if (_selectedOption == indexPath.row) {
        UIImageView* disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(282, 14.5, 20, 19)];
        disclosure.image = [UIImage imageNamed:@"checkmark.png"];
        disclosure.backgroundColor = [UIColor clearColor];
        [cell.contentView addSubview:disclosure];
    }

    UIView* sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:.8
                                            alpha:1];
    [cell.contentView addSubview:sep];

    return cell;
}

- (void)tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath
                             animated:YES];
    NSUInteger prev = _selectedOption;
    _selectedOption = indexPath.row;
    if (_selectedOption != prev) {
        [self.tableView reloadRowsAtIndexPaths:@[
                                                   [NSIndexPath indexPathForRow:prev
                                                                      inSection:0],
                                                   [NSIndexPath indexPathForRow:_selectedOption
                                                                      inSection:0]
                                               ]
                              withRowAnimation:UITableViewRowAnimationAutomatic];
    }
    if (self.delegate && [self.delegate respondsToSelector:@selector(optionSelectController:
                                                                            didSelectOption:)]) {
        [self.delegate optionSelectController:self
                              didSelectOption:_selectedOption];
    }
}

@end
