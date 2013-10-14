//
//  FFInviteViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/28/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFInviteViewController.h"
#import "FFBubblePicker.h"
#import <RHAddressBook/AddressBook.h>
#import "FFAlertView.h"
#import "FFSessionViewController.h"

@interface FFInviteViewController ()
<FFBubblePickerDelegate, UITextViewDelegate, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic) FFBubblePicker *bubblePicker;
@property (nonatomic) UITextView *message;
@property (nonatomic) NSPredicate *searchPredicate;
@property (nonatomic) UITableView *autocompleteView;
@property (nonatomic) NSArray *contacts;
@property (nonatomic) NSArray *allContacts;
@property (nonatomic) UIView *lowerHalf;
@property (nonatomic) UIScrollView *scrollView;

@end

@implementation FFInviteViewController

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
    
    UILabel *titleLab = [[UILabel alloc] initWithFrame:CGRectMake(15, 44, 290, 50)];
    titleLab.text = NSLocalizedString(@"Invite Players", nil);
    titleLab.font = [FFStyle lightFont:26];
    titleLab.textColor = [FFStyle tableViewSectionHeaderColor];
    [self.view addSubview:titleLab];
    
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(15, 94, 290, 1)];
    sep.backgroundColor = [FFStyle tableViewSeparatorColor];
    [self.view addSubview:sep];
    
    _scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, CGRectGetMaxY(titleLab.frame), 320,
                                                                 self.view.frame.size.height
                                                                 -CGRectGetMaxY(titleLab.frame))];
    _scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:_scrollView];
    
    if ([self respondsToSelector:@selector(topLayoutGuide)]) {
        [_scrollView setTranslatesAutoresizingMaskIntoConstraints:NO];
        titleLab.translatesAutoresizingMaskIntoConstraints = NO;
        sep.translatesAutoresizingMaskIntoConstraints = NO;
        id topGuide = self.topLayoutGuide;
        id bottomGuide = self.bottomLayoutGuide;
        NSDictionary *viewsDictionary = NSDictionaryOfVariableBindings(_scrollView, topGuide, bottomGuide, titleLab, sep);
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[topGuide][titleLab(44)][sep(1)][_scrollView][bottomGuide]"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:viewsDictionary]];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_scrollView]|"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:viewsDictionary]];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-15-[titleLab]-15-|"
                                                                          options:0 metrics:nil views:viewsDictionary]];
    } else {
        _scrollView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    }
    
    UILabel *toLab = [[UILabel alloc] initWithFrame:CGRectMake(15, 5, 50, 30)];
    toLab.text = NSLocalizedString(@"To:", nil);
    toLab.font = [FFStyle regularFont:17];
//    [toLab sizeToFit];
    toLab.textColor = [FFStyle greyTextColor];
//    toLab.backgroundColor = [UIColor blueColor];
    [_scrollView addSubview:toLab];
    
    _bubblePicker = [[FFBubblePicker alloc] init];
    _bubblePicker.frame = CGRectMake(42, 7, 265, 30);
    _bubblePicker.delegate = self;
//    _bubblePicker.backgroundColor = [UIColor redColor];
    [_scrollView addSubview:_bubblePicker];
    
    _lowerHalf = [[UIView alloc] initWithFrame:CGRectMake(0, 44, 320, 400)];
    [_scrollView addSubview:_lowerHalf];
    
    UILabel *msgLab = [[UILabel alloc] initWithFrame:CGRectMake(15, 0, 100, 45)];
    msgLab.text = NSLocalizedString(@"Message:", nil);
    msgLab.font = [FFStyle regularFont:17];
    msgLab.textColor = [FFStyle greyTextColor];
//    msgLab.backgroundColor = [UIColor greenColor];
    [_lowerHalf addSubview:msgLab];
    
    _message = [[UITextView alloc] initWithFrame:CGRectMake(10, 8, 300, 120)];
//    _message.backgroundColor = [UIColor yellowColor];
    _message.editable = YES;
    _message.delegate = self;
    _message.font = [FFStyle regularFont:16];
    _message.text = NSLocalizedString(@"You can customize the message to your friends here.", nil);
    [_lowerHalf addSubview:_message];
    
    _autocompleteView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, 320, 213) style:UITableViewStylePlain];
    _autocompleteView.delegate = self;
    _autocompleteView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _autocompleteView.dataSource = self;
    [_autocompleteView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [_lowerHalf addSubview:_autocompleteView];
    
    sep = [[UIView alloc] initWithFrame:CGRectMake(15, 0, 290, 1)];
    sep.backgroundColor = [FFStyle tableViewSeparatorColor];
    [_lowerHalf addSubview:sep];
    
    // -----
    
//    UINavigationBar *navBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
//    [self.view addSubview:navBar];
    
//    UIButton *closeButt = [UIButton buttonWithType:UIButtonTypeCustom];
//    closeButt.titleLabel.font = [FFStyle regularFont:15];
//    closeButt.titleLabel.textColor = [FFStyle white];
//    closeButt.frame = CGRectMake(0, 0, 56, 44);
//    [closeButt setTitle:NSLocalizedString(@"Close", nil) forState:UIControlStateNormal];
//    [closeButt addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
//    
//    UIButton *sendButt = [UIButton buttonWithType:UIButtonTypeCustom];
//    sendButt.titleLabel.font = [FFStyle regularFont:15];
//    sendButt.titleLabel.textColor = [FFStyle white];
//    sendButt.frame = CGRectMake(0, 0, 56, 44);
//    [sendButt setTitle:NSLocalizedString(@"Send", nil) forState:UIControlStateNormal];
//    [sendButt addTarget:self action:@selector(send:) forControlEvents:UIControlEventTouchUpInside];
//
//    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithCustomView:closeButt];
//    UIBarButtonItem *send = [[UIBarButtonItem alloc] initWithCustomView:sendButt];
//    UINavigationItem *item = [[UINavigationItem alloc] initWithTitle:@""];
//    [navBar pushNavigationItem:item animated:NO];
//    item.leftBarButtonItem = close;
//    item.rightBarButtonItem = send;
    
//    UIButton *cancel = [FFStyle clearButtonWithText:NSLocalizedString(@"Close", nil) borderColor:[FFStyle white]];
//    cancel.frame = CGRectMake(0, 0, 70, 30);
//    [cancel addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
//    
//    UIButton *create = [FFStyle clearButtonWithText:NSLocalizedString(@"Send", nil) borderColor:[FFStyle white]];
//    create.frame = CGRectMake(0, 0, 70, 30);
//    [create addTarget:self action:@selector(send:) forControlEvents:UIControlEventTouchUpInside];
    
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    [logo sizeToFit];
    
    self.navigationItem.titleView = logo;
    self.navigationItem.leftBarButtonItems = [FFStyle clearNavigationBarButtonWithText:NSLocalizedString(@"Close", nil)
                                                                           borderColor:[FFStyle white] target:self
                                                                              selector:@selector(close:)
                                                                         leftElseRight:YES];
    self.navigationItem.rightBarButtonItems = [FFStyle clearNavigationBarButtonWithText:NSLocalizedString(@"Send", nil)
                                                                            borderColor:[FFStyle white] target:self
                                                                               selector:@selector(send:)
                                                                          leftElseRight:NO];
    
//    item.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];
//    item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:create];
//    item.titleView = logo;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    if (!_roster) {
        @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                       reason:@"Gotta give me a roster so i can invite something"
                                     userInfo:nil];
    }
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self _reloadAutocomplete];
    [_bubblePicker openAutocomplete];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)send:(UIButton *)sender
{
    if (!_bubblePicker.items.count) {
        FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"You need to add at least one "
                                                                                  @"contact to send an invite.", nil)
                                                        message:nil cancelButtonTitle:nil
                                                okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                       autoHide:YES];
        [alert showInView:self.view];
        return;
    }
    
    FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Sending Invites", nil)
                                                   messsage:nil loadingStyle:FFAlertViewLoadingStylePlain];
    [alert showInView:self.view];
    
    NSString *path = [NSString stringWithFormat:@"/contests/%@/invite", _roster.contest[@"id"]];
    NSMutableArray *emails = [NSMutableArray array];
    for (NSArray *contact in _bubblePicker.items) {
        [emails addObject:contact[1]];
    }
    NSDictionary *params = @{@"invitees": emails, @"invitation_code": _roster.contest[@"invitation_code"]};
    [self.session authorizedJSONRequestWithMethod:@"POST" path:path paramters:params success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         [alert hide];
         FFAlertView *falert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Success", nil)
                                                          message:NSLocalizedString(@"Your friends will be notified!",
                                                                                    nil)];
         [falert showInView:self.view];
         double delayInSeconds = 1.5;
         dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
         dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
             [falert hide];
             [self close:nil];
         });
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         [alert hide];
         FFAlertView *ealert = [[FFAlertView alloc] initWithError:error
                                                            title:nil
                                                cancelButtonTitle:nil
                                                  okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                         autoHide:YES];
         [ealert showInView:self.view];
     }];
}

- (void)close:(UIButton *)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text
{
    if ([text isEqualToString:@"\n"]) {
        [textView resignFirstResponder];
        return NO;
    }
    return YES;
}

//
// bubble picker and autocomplete --------------------------------------------------------------------------------------
//

- (void)_reloadAutocompleteSearchResults
{
    if (_searchPredicate) {
        _contacts = [_allContacts filteredArrayUsingPredicate:_searchPredicate];
    } else {
        _contacts = _allContacts;
    }
    [_autocompleteView reloadData];
}

- (void)_reloadAutocomplete
{
    RHAddressBook *book = [[RHAddressBook alloc] init];
    if (![RHAddressBook authorizationStatus] != RHAuthorizationStatusAuthorized) {
        __strong FFInviteViewController *strongSelf = self;
        [book requestAuthorizationWithCompletion:^(bool granted, NSError *error) {
            if (!granted) {
                NSString *msg = NSLocalizedString(@"We need access to your contacts so we can search the email address."
                                                  @"We won't scrape your address book and we won't send any emails to "
                                                  @"members of your address book unless you specify them in invitations."
                                                  , nil);
                FFAlertView *alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Error", nil)
                                                                message:msg
                                                      cancelButtonTitle:nil
                                                        okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                               autoHide:YES];
                [alert showInView:strongSelf.view];
            } else {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSMutableArray *contacts = [NSMutableArray array];
                    // we duplicate users w/ multiple email addresses
                    for (RHPerson *person in [book peopleOrderedByUsersPreference]) {
                        NSArray *allEmails = person.emails.values;
                        for (NSString *email in allEmails) {
                            [contacts addObject:@[person, email]];
                        }
                    }
                    strongSelf->_allContacts = contacts;
                    [strongSelf _reloadAutocompleteSearchResults];
                });
            }
        }];
    } else {
        _allContacts = [book peopleOrderedByUsersPreference];
    }
}

- (void)bubblePickerDidUpdateItems:(FFBubblePicker *)picker
{

}

- (void)bubblePicker:(id)picker willUpdateHeight:(CGFloat)height
{
    CGRect bpframe = _bubblePicker.frame;
    bpframe.size.height = height;
    _bubblePicker.frame = bpframe;
    [UIView animateWithDuration:.2 animations:^{
        _lowerHalf.frame = CGRectMake(0, CGRectGetMaxY(bpframe)+7, 320, 400);
    }];
}

- (void)bubblePicker:(FFBubblePicker *)picker didSelectItem:(id)item
{
    [picker removeItem:item animated:YES];
}

- (void)bubblePickerWillBeginEditing:(FFBubblePicker *)picker
{
    [self _reloadAutocomplete];
    [_autocompleteView setUserInteractionEnabled:YES];
    [_autocompleteView setAlpha:1];
    
    [self bubblePicker:picker didUpdateText:@""];
}

- (void)bubblePickerDidEndEditing:(FFBubblePicker *)picker
{
    [_autocompleteView setUserInteractionEnabled:NO];
    [_autocompleteView setAlpha:0];
    _contacts = nil;
}

- (void)bubblePicker:(FFBubblePicker *)picker didUpdateText:(NSString *)text
{
    if (!text.length) {
        [_autocompleteView setUserInteractionEnabled:NO];
        [_autocompleteView setAlpha:0];
        _searchPredicate = nil;
        _contacts = nil;
        [_autocompleteView reloadData];
    } else {
        NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(id evaluatedObject, NSDictionary *bindings) {
            RHPerson *contact = evaluatedObject[0];
            for (NSString *token in [text componentsSeparatedByCharactersInSet:
                                     [NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
                // first name match
                NSRange fnRange = [contact.firstName rangeOfString:token options:NSCaseInsensitiveSearch];
                if (contact.firstName && fnRange.location != NSNotFound) {
                    return YES;
                }
                // last name match
                NSRange lnRange = [contact.lastName rangeOfString:token options:NSCaseInsensitiveSearch];
                if (contact.lastName && lnRange.location != NSNotFound) {
                    return YES;
                }
                // first name match
                NSRange fnRangeP = [contact.firstNamePhonetic rangeOfString:token options:NSCaseInsensitiveSearch];
                if (contact.firstNamePhonetic && fnRangeP.location != NSNotFound) {
                    return YES;
                }
                // last name match
                NSRange lnRangeP = [contact.lastNamePhonetic rangeOfString:token options:NSCaseInsensitiveSearch];
                if (contact.lastNamePhonetic && lnRangeP.location != NSNotFound) {
                    return YES;
                }
                // email match
                NSRange emRange = [evaluatedObject[1] rangeOfString:token options:NSCaseInsensitiveSearch];
                if (emRange.location != NSNotFound) {
                    return YES;
                }
            }
            return NO;
        }];
        [_autocompleteView setUserInteractionEnabled:YES];
        [_autocompleteView setAlpha:1];
        _searchPredicate = predicate;
        [self _reloadAutocompleteSearchResults];
    }
}

//
// autocomplete table view ---------------------------------------------------------------------------------------------
//
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger add = 0;
    
    // add 1 for the email if the currently entered value is an email address
    __strong static NSRegularExpression *regex = nil;
    if (regex == nil) {
        NSError *error = nil;
        NSString *emailRe = FF_EMAIL_REGEX;
        regex = [NSRegularExpression regularExpressionWithPattern:emailRe
                                                          options:NSRegularExpressionCaseInsensitive
                                                            error:&error];
        if (error) {
            @throw [NSException exceptionWithName:NSInternalInconsistencyException
                                           reason:@"Could not compile regex"
                                         userInfo:NSDictionaryOfVariableBindings(emailRe)];
        }
    }
    NSString *txt = [_bubblePicker.textViewValue copy];
    NSTextCheckingResult *result = [regex firstMatchInString:txt options:0 range:NSMakeRange(0, txt.length)];
    if (result.range.length) {
        add += 1;
    }
    
    return [_contacts count] + add;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 54;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    NSString *title;
    
    if (indexPath.row < _contacts.count) {
        RHPerson *person = _contacts[indexPath.row][0];
        title = [NSString stringWithFormat:@"%@ %@", person.firstName, person.lastName];
    } else {
        title = _bubblePicker.textViewValue;
    }
    
    UILabel *lab = [[UILabel alloc] initWithFrame:CGRectMake(15, 3, 290, 30)];
    lab.backgroundColor = [UIColor clearColor];
    lab.font = [FFStyle regularFont:17];
    lab.text = title;
    lab.textColor = [FFStyle darkGreyTextColor];
    [cell.contentView addSubview:lab];
    
    UILabel *elab = [[UILabel alloc] initWithFrame:CGRectMake(15, 28, 290, 20)];
    elab.backgroundColor = [UIColor clearColor];
    elab.font = [FFStyle regularFont:13];
    elab.textColor = [FFStyle greyTextColor];
    if (indexPath.row < _contacts.count) {
        elab.text = _contacts[indexPath.row][1];
    } else {
        elab.text = @"";
    }
    [cell.contentView addSubview:elab];
    
    UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(15, 53, 290, 1)];
    sep.backgroundColor = [FFStyle tableViewSeparatorColor];
    [cell.contentView addSubview:sep];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.row < _contacts.count) {
        RHPerson *person = _contacts[indexPath.row][0];
        NSString *title = [NSString stringWithFormat:@"%@ %@", person.firstName, person.lastName];
    
        [_bubblePicker addItem:_contacts[indexPath.row] title:title animated:YES];
    } else {
        NSString *title = _bubblePicker.textViewValue;
        [_bubblePicker addItem:@[[NSNull null], [title copy]] title:[title copy] animated:YES];
    }
    [_bubblePicker resetTextView];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end
