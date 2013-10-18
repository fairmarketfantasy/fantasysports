//
//  FFMyAccountViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 10/3/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFMyAccountViewController.h"
#import "FFSessionViewController.h"
#import "FFValueEntryController.h"
#import "FFAlertView.h"
#import <MobileCoreServices/UTCoreTypes.h>


@interface FFMyAccountViewController ()
<UITableViewDataSource, UITableViewDelegate, FFValueEntryControllerDelegate,
UIImagePickerControllerDelegate, UINavigationControllerDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) FFAlertView *alert;
@property (nonatomic) BOOL shouldSave;

@end


@implementation FFMyAccountViewController

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
	// Do any additional setup after loading the view.
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
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    
    UIButton *balanceView = [self.sessionController balanceView];
    [balanceView addTarget:self action:@selector(showBalance:) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:balanceView];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}


- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 5;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (section == 0) {
        return 0;
    }
    if (section == 4) {
        return 2;
    }
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == 1) {
        return 50;
    }
    return 44;
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
        lab.text = NSLocalizedString(@"Settings", nil);
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
            lab.text = NSLocalizedString(@"Avatar", nil);
        } else if (section == 2) {
            lab.text = NSLocalizedString(@"Name", nil);
        } else if (section == 3) {
            lab.text = NSLocalizedString(@"Email Address", nil);
        } else if (section == 4) {
            lab.text = NSLocalizedString(@"", nil);
        }
        [header addSubview:lab];
        return header;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];

    UIImageView *disclosure = [[UIImageView alloc] initWithFrame:CGRectMake(295, 14.5, 10, 15)];
    disclosure.image = [UIImage imageNamed:@"disclosurelight.png"];
    disclosure.backgroundColor = [UIColor clearColor];
    [cell.contentView addSubview:disclosure];
    cell.selectionStyle = UITableViewCellSelectionStyleBlue;
    
    FFUser *user = (FFUser *)self.session.user;
    
    if (indexPath.section == 1) {
        UIImageView *imgView = [[UIImageView alloc] initWithFrame:CGRectMake(15, 5, 40, 40)];
        [cell.contentView addSubview:imgView];
        
        NSURL *url = [NSURL URLWithString:user.imageUrl];
        [imgView setImageWithURL:url placeholderImage:[UIImage imageNamed:@"defaultuser.png"]];
    }
    else if (indexPath.section == 2) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
        lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        lab.font = [FFStyle regularFont:17];
        lab.textColor = [FFStyle darkGreyTextColor];
        [cell.contentView addSubview:lab];
        if (user.name != nil && user.name.length) {
            lab.text = user.name;
        } else {
            lab.text = NSLocalizedString(@"No Name Set", nil);
        }
    }
    else if (indexPath.section == 3) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
        lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        lab.font = [FFStyle regularFont:17];
        lab.textColor = [FFStyle darkGreyTextColor];
        [cell.contentView addSubview:lab];
        lab.text = user.email;
    }
    else if (indexPath.section == 4) {
        UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 320, cell.contentView.frame.size.height)];
        lab.autoresizingMask = UIViewAutoresizingFlexibleHeight;
        lab.font = [FFStyle regularFont:17];
        lab.textColor = [FFStyle darkGreyTextColor];
        [cell.contentView addSubview:lab];
        
        if (indexPath.row == 0) {
            lab.text = NSLocalizedString(@"Change Password", nil);
        }
//        else if (indexPath.row == 1) {
//            lab.text = NSLocalizedString(@"Delete Account", nil);
//        }
        else if (indexPath.row == 1) {
            lab.text = NSLocalizedString(@"Sign out", nil);
        }
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    if (indexPath.section == 1) {
        UIButton *camera = [FFAlertView blueButtonTitled:NSLocalizedString(@"Take Photo", nil)];
        [camera addTarget:self action:@selector(takePhoto:) forControlEvents:UIControlEventTouchUpInside];
        if (![UIImagePickerController isSourceTypeAvailable:UIImagePickerControllerSourceTypeCamera]) {
            camera.enabled = NO;
            camera.alpha = .3;
        }
        
        UIButton *roll = [FFAlertView blueButtonTitled:NSLocalizedString(@"Choose Photo", nil)];
        [roll addTarget:self action:@selector(choosePhoto:) forControlEvents:UIControlEventTouchUpInside];
        
        UIButton *cancel = [FFAlertView greyButtonTitled:NSLocalizedString(@"Cancel", nil)];
        [cancel addTarget:self action:@selector(cancelPhoto:) forControlEvents:UIControlEventTouchUpInside];
        
        _alert = [[FFAlertView alloc] initWithTitle:nil
                                                        message:nil buttons:@[camera, roll, cancel]];
        [_alert showInView:self.navigationController.view];
    }
    else if (indexPath.section == 2) {
        [self performSegueWithIdentifier:@"GotoName" sender:nil];
    }
    else if (indexPath.section == 3) {
        [self performSegueWithIdentifier:@"GotoEmail" sender:nil];
    }
    else if (indexPath.section == 4) {
        if (indexPath.row == 1) {
            [self.session logout];
        }
    }
}

- (void)takePhoto:(id)s
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypeCamera;
    picker.mediaTypes = [NSArray arrayWithObject:(id)kUTTypeImage];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)choosePhoto:(id)s
{
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.mediaTypes = [NSArray arrayWithObject:(id)kUTTypeImage];
    picker.delegate = self;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)imagePickerController:(UIImagePickerController *)picker didFinishPickingMediaWithInfo:(NSDictionary *)info
{
//    UIImage *img = info[UIImagePickerControllerOriginalImage];

    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)cancelPhoto:(id)s
{
    [_alert hide];
    _alert = nil;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    FFUser *user = (FFUser *)self.session.user;
    if ([segue.identifier isEqualToString:@"GotoName"]) {
        FFValueEntryController *c = segue.destinationViewController;
        c.keyboardType = UIKeyboardTypeDefault;
        c.autocapitalizationType = UITextAutocapitalizationTypeWords;
        c.value = user.name;
        c.name = segue.identifier;
        c.delegate = self;
        c.sectionTitle = NSLocalizedString(@"Set Name", nil);
    }
    else if ([segue.identifier isEqualToString:@"GotoEmail"]) {
        FFValueEntryController *c = segue.destinationViewController;
        c.keyboardType = UIKeyboardTypeEmailAddress;
        c.autocapitalizationType = UITextAutocapitalizationTypeNone;
        c.value = user.email;
        c.name = segue.identifier;
        c.delegate = self;
        c.sectionTitle = NSLocalizedString(@"Set Email", nil);
    }
    _shouldSave = YES;
}

- (void)valueEntryController:(FFValueEntryController *)cont didEnterValue:(NSString *)value
{
    FFUser *user = (FFUser *)self.session.user;
    if ([cont.name isEqualToString:@"GotoName"]) {
        user.name = value;
    }
    else if ([cont.name isEqualToString:@"GotoEmail"]) {
        user.email = value;
    }
    [self.tableView reloadData];
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)valueEntryController:(FFValueEntryController *)cont didUpdateValue:(NSString *)value
{
    FFUser *user = (FFUser *)self.session.user;
    if ([cont.name isEqualToString:@"GotoName"]) {
        user.name = value;
    }
    else if ([cont.name isEqualToString:@"GotoEmail"]) {
        user.email = value;
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    if (_shouldSave) {
        FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Saving", nil) messsage:nil
                                                   loadingStyle:FFAlertViewLoadingStylePlain];
        [alert showInView:self.navigationController.view];
        FFUser *user = (FFUser *)self.session.user;
        [user updateInBackgroundWithBlock:^(id successObj) {
            [alert hide];
        } failure:^(NSError *error) {
            [alert hide];
            FFAlertView *ealert = [[FFAlertView alloc] initWithError:error title:nil cancelButtonTitle:nil
                                                     okayButtonTitle:NSLocalizedString(@"Dismiss", nil) autoHide:YES];
            [ealert showInView:self.navigationController.view];
        }];
        _shouldSave = NO;
    }
}

@end
