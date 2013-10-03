//
//  FFTokenPurchaseViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 10/3/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTokenPurchaseViewController.h"
#import "FFSessionViewController.h"
#import "FFAlertView.h"
//#import <IAPManager/IAPManager.h>
#import <StoreKit/StoreKit.h>
#import "NSData+Base64.h"


@interface FFTokenPurchaseViewController ()
<UITableViewDataSource, UITableViewDelegate, SKPaymentTransactionObserver, SKProductsRequestDelegate>

@property (nonatomic) UITableView *tableView;
@property (nonatomic) NSArray *purchaseItems;
@property (nonatomic) FFAlertView *alert;
@property (nonatomic) NSArray *skus;
@property (nonatomic) BOOL restoring;

@end


@implementation FFTokenPurchaseViewController

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
    _tableView = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width,
                                                               self.view.frame.size.height)];
    _tableView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    _tableView.backgroundColor = [UIColor clearColor];
    _tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    _tableView.dataSource = self;
    _tableView.delegate = self;
    [_tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"Cell"];
    [self.view addSubview:_tableView];
    
    UIButton *cancel = [FFStyle clearButtonWithText:NSLocalizedString(@"Close", nil) borderColor:[FFStyle white]];
    cancel.frame = CGRectMake(0, 0, 70, 30);
    [cancel addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:cancel];
    
    UIButton *balanceView = [self.sessionController balanceView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:balanceView];
    
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    [logo sizeToFit];
    self.navigationItem.titleView = logo;
}

- (void)close:(UIButton *)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [[SKPaymentQueue defaultQueue] addTransactionObserver:self];
    _restoring = YES;
    
    if (![SKPaymentQueue canMakePayments]) {
        FFAlertView *alert =[[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Error", nil)
                                                        message:NSLocalizedString(@"Purchasing is not enabled for this Apple account", nil)
                                              cancelButtonTitle:nil okayButtonTitle:NSLocalizedString(@"Dismiss", nil) autoHide:YES];
        [alert showInView:self.view];
        return;
    }
    
    _alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Loading", nil)
                                                   messsage:nil
                                               loadingStyle:FFAlertViewLoadingStylePlain];
    [_alert showInView:self.view];
    
    [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/users/token_plans" paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         
         _skus = [JSON allKeys];
         [self getProducts];

     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         [_alert hide];
         FFAlertView *ealert = [[FFAlertView alloc] initWithError:error title:nil
                                                cancelButtonTitle:nil
                                                  okayButtonTitle:NSLocalizedString(@"Dismiss", nil)
                                                         autoHide:YES];
         [ealert showInView:self.view];
     }];
}

- (void)getProducts
{
    SKProductsRequest *req = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:_skus]];
    req.delegate = self;
    [req start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    _purchaseItems = response.products;
    [_tableView reloadData];
    if (_alert) {
        [_alert hide];
        _alert = nil;
    }
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
    if (self.purchaseItems) {
        return self.purchaseItems.count;
    }
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60;
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
    lab.text = NSLocalizedString(@"Purchase Tokens", nil);
    [header addSubview:lab];
    return header;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];
    [cell.contentView.subviews makeObjectsPerformSelector:@selector(removeFromSuperview)];
    
    SKProduct *prod = self.purchaseItems[indexPath.row];
    cell.textLabel.text = prod.localizedTitle;
    
    NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
    [numberFormatter setFormatterBehavior:NSNumberFormatterBehavior10_4];
    [numberFormatter setNumberStyle:NSNumberFormatterCurrencyStyle];
    [numberFormatter setLocale:prod .priceLocale];
    NSString *formattedString = [numberFormatter stringFromNumber:prod.price];
    
    FFCustomButton *_select = [FFStyle coloredButtonWithText:formattedString
                                                       color:[FFStyle brightGreen]
                                                 borderColor:[FFStyle white]];
    _select.tag = indexPath.row; // the tag is what index is selected
    _select.frame = CGRectMake(224, 21, 80, 38);
    [_select addTarget:self action:@selector(select:) forControlEvents:UIControlEventTouchUpInside];
    [cell.contentView addSubview:_select];
    
    return cell;
}

- (void)select:(UIButton *)sender
{
    _alert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Purchasing", nil)
                                       messsage:nil
                                   loadingStyle:FFAlertViewLoadingStylePlain];
    [_alert showInView:self.view];
    
    SKProduct *product = self.purchaseItems[sender.tag];
    SKPayment *payment = [SKPayment paymentWithProduct:product];
    [[SKPaymentQueue defaultQueue] addPayment:payment];
    
//    [[IAPManager sharedIAPManager] purchaseProduct:product completion:^(SKPaymentTransaction *transaction) {
//        NSDictionary *params = @{@"receipt": [transaction.transactionReceipt base64EncodedString]};
//        
//        [self.session authorizedJSONRequestWithMethod:@"POST" path:@"/users/add_tokens" paramters:params success:
//         ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
//             [alert hide];
//             FFAlertView *salert = [[FFAlertView alloc] initWithTitle:NSLocalizedString(@"Success", nil)
//                                                              message:NSLocalizedString(@"Your purchase was successful. "
//                                                                                        @"Your balance will be updated shortly.", nil)];
//             [salert showInView:self.view];
//             double delayInSeconds = 1.5;
//             dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
//             dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
//                 [salert hide];
//             });
//         } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
//             [alert hide];
//             FFAlertView *ealert = [[FFAlertView alloc] initWithError:error
//                                                                title:nil
//                                                    cancelButtonTitle:nil
//                                                      okayButtonTitle:NSLocalizedString(@"Dissmiss", nil)
//                                                             autoHide:YES];
//             [ealert showInView:self.view];
//         }];
//    } error:^(NSError *error) {
//        [alert hide];
//        FFAlertView *ealert = [[FFAlertView alloc] initWithError:error
//                                                           title:nil
//                                               cancelButtonTitle:nil
//                                                 okayButtonTitle:NSLocalizedString(@"Dissmiss", nil)
//                                                        autoHide:YES];
//        [ealert showInView:self.view];
//    }];
}

- (void)paymentQueue:(SKPaymentQueue *)queue removedTransactions:(NSArray *)transactions
{
    NSLog(@"removed transactions %@", transactions);
}

- (void)paymentQueue:(SKPaymentQueue *)queue restoreCompletedTransactionsFailedWithError:(NSError *)error
{
    NSLog(@"restore completed transactions failed %@", error);
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedDownloads:(NSArray *)downloads
{
    NSLog(@"update downloads %@", downloads);
}

- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    NSLog(@"updated transactions %@", transactions);

    for (SKPaymentTransaction *t in transactions) {
        switch (t.transactionState) {
            case SKPaymentTransactionStatePurchased:
                NSLog(@"transaction purchased %@ %@", t, t.payment);
                [self addTokens:t];
                break;
            case SKPaymentTransactionStateRestored:
                NSLog(@"transaction restored %@ %@", t, t.payment);
                break;
            case SKPaymentTransactionStatePurchasing:
                NSLog(@"transaction purchasing %@ %@", t, t.payment);
                break;
            case SKPaymentTransactionStateFailed:
                NSLog(@"transaction failed %@ %@ %@", t, t.payment, t.error);
                break;
            default:
                break;
        }
    }
}

- (void)addTokens:(SKPaymentTransaction *)transaction
{
    NSLog(@"add tokens %@", transaction);
    
    NSDictionary *params = @{@"receipt": [transaction.transactionReceipt base64EncodedString]};
    NSLog(@"params %@", params);
    
    [self.session authorizedJSONRequestWithMethod:@"POST" path:@"/users/add_tokens" paramters:params success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         
         [[SKPaymentQueue defaultQueue] finishTransaction:transaction];
         
         [[SKPaymentQueue defaultQueue] restoreCompletedTransactions];
         
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         NSLog(@"error verifying transaction %@", error);
     }];
}

- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSLog(@"restore completed transactions finished");
}

@end
