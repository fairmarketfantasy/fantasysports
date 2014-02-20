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

@property(nonatomic) UITableView* tableView;
@property(nonatomic) UITextField* textField;

@end

@implementation FFValueEntryController

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
    return 1;
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

    UITextField* field = _textField = [[FFTextField alloc] initWithFrame:CGRectMake(15, 4, 290, 38)];
    field.borderStyle = UITextBorderStyleNone;
    field.font = [FFStyle regularFont:17];
    field.textColor = [FFStyle darkGreyTextColor];
    field.delegate = self;
    field.keyboardType = self.keyboardType;
    field.autocapitalizationType = self.autocapitalizationType;
    [cell.contentView addSubview:field];

    UIToolbar* tb = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
    tb.items = @[
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                      target:nil
                                                      action:NULL],
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone
                                                      target:self
                                                      action:@selector(done:)]
    ];

    field.inputAccessoryView = tb;

    UIView* sep = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:.8
                                            alpha:1];
    [cell.contentView addSubview:sep];

    sep = [[UIView alloc] initWithFrame:CGRectMake(0, cell.contentView.frame.size.height - 1, 320, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:.8
                                            alpha:1];
    cell.autoresizingMask = UIViewAutoresizingFlexibleTopMargin;
    [cell.contentView addSubview:sep];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    return cell;
}

- (void)tableView:(UITableView*)tableView willDisplayCell:(UITableViewCell*)cell forRowAtIndexPath:(NSIndexPath*)indexPath
{
    [cell.contentView.subviews[0] becomeFirstResponder];
}

- (void)done:(UIControl*)sender
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(valueEntryController:
                                                                            didEnterValue:)]) {
        [self.delegate valueEntryController:self
                              didEnterValue:_textField.text];
    }
}

- (BOOL)textField:(UITextField*)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString*)string
{
    if (self.delegate && [self.delegate respondsToSelector:@selector(valueEntryController:
                                                                           didUpdateValue:)]) {
        NSString* ns = [textField.text stringByReplacingCharactersInRange:range
                                                               withString:string];
        [self.delegate valueEntryController:self
                             didUpdateValue:ns];
    }
    return YES;
}

@end
