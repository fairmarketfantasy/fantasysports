//
//  FFWebViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 10/3/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFWebViewController.h"


@interface FFWebViewController () <UIWebViewDelegate>

@property (strong, nonatomic) UIWebView *webView;

@property (strong, nonatomic) UIBarButtonItem *stopLoadingButton;
@property (strong, nonatomic) UIBarButtonItem *reloadButton;
@property (strong, nonatomic) UIBarButtonItem *backButton;
@property (strong, nonatomic) UIBarButtonItem *forwardButton;

@end


@implementation FFWebViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)load
{
    NSURLRequest *request = [NSURLRequest requestWithURL:self.URL];
    [self.webView loadRequest:request];
    
    if (self.navigationController.toolbarHidden) {
        [self.navigationController setToolbarHidden:NO animated:YES];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];

//    UIButton *cancel = [FFStyle clearNavigationBarButtonWithText:NSLocalizedString(@"Close", nil) borderColor:[FFStyle white]];
//    cancel.frame = CGRectMake(0, 0, 70, 30);
//    [cancel addTarget:self action:@selector(close:) forControlEvents:UIControlEventTouchUpInside];
//    
//    UIBarButtonItem *close = [[UIBarButtonItem alloc] initWithCustomView:cancel];
    
    self.navigationItem.leftBarButtonItems = [FFStyle clearNavigationBarButtonWithText:NSLocalizedString(@"Close", nil)
                                                                           borderColor:[FFStyle white]
                                                                                target:self
                                                                              selector:@selector(close:)
                                                                         leftElseRight:YES];
    [self setupToolBarItems];
    
    self.webView = [[UIWebView alloc] initWithFrame:self.view.bounds];
    self.webView.scalesPageToFit = YES;
    [self.view addSubview:self.webView];
    
    if ([self respondsToSelector:@selector(topLayoutGuide)]) {
        [_webView setTranslatesAutoresizingMaskIntoConstraints:NO];
        id topGuide = self.topLayoutGuide;
        id bottomGuide = self.bottomLayoutGuide;
        NSDictionary *viewsDictionary = NSDictionaryOfVariableBindings(_webView, topGuide, bottomGuide);
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[topGuide][_webView][bottomGuide]"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:viewsDictionary]];
        [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_webView]|"
                                                                          options:0
                                                                          metrics:nil
                                                                            views:viewsDictionary]];
    } else {
        _webView.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
    }
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.webView.delegate = self;
    self.URL = [NSURL URLWithString:@"http://google.com"];
    if (self.URL) {
        [self load];
    }
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.webView stopLoading];
    self.webView.delegate = nil;
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
}

#pragma mark - Helpers

- (UIImage *)leftTriangleImage
{
    static UIImage *image;
    
    static dispatch_once_t predicate;
    dispatch_once(&predicate, ^{
        CGSize size = CGSizeMake(14.0f, 16.0f);
        UIGraphicsBeginImageContextWithOptions(size, NO, 0.0f);
        
        UIBezierPath *path = [UIBezierPath bezierPath];
        [[UIColor whiteColor] set];
        [path moveToPoint:CGPointMake(0.0f, 8.0f)];
        [path addLineToPoint:CGPointMake(14.0f, 0.0f)];
        [path addLineToPoint:CGPointMake(14.0f, 16.0f)];
        [path closePath];
        [path fill];
        
        image = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    
    return image;
}

- (UIImage *)rightTriangleImage
{
    UIImage *image = [self leftTriangleImage];
    return [UIImage imageWithCGImage:image.CGImage scale:image.scale orientation:UIImageOrientationDown];
}

- (void)setupToolBarItems
{
    self.stopLoadingButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                                           target:self.webView
                                                                           action:@selector(stopLoading)];
    
    self.reloadButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh
                                                                      target:self.webView
                                                                      action:@selector(reload)];
    
    self.backButton = [[UIBarButtonItem alloc] initWithImage:[self leftTriangleImage]
                                                       style:UIBarButtonItemStylePlain
                                                      target:self.webView
                                                      action:@selector(goBack)];
    
    self.forwardButton = [[UIBarButtonItem alloc] initWithImage:[self rightTriangleImage]
                                                          style:UIBarButtonItemStylePlain
                                                         target:self.webView
                                                         action:@selector(goForward)];
    
    self.backButton.enabled = NO;
    self.forwardButton.enabled = NO;
    
    UIBarButtonItem *actionButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                                                  target:self
                                                                                  action:@selector(action:)];
    
    UIBarButtonItem *space = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                           target:nil
                                                                           action:nil];
    
    UIBarButtonItem *space_ = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                            target:nil
                                                                            action:nil];
    space_.width = 60.0f;
    
    self.toolbarItems = @[self.stopLoadingButton, space]; // , self.backButton, space_, self.forwardButton, space, actionButton];
}

- (void)toggleState
{
    self.backButton.enabled = self.webView.canGoBack;
    self.forwardButton.enabled = self.webView.canGoForward;
    
    NSMutableArray *toolbarItems = [self.toolbarItems mutableCopy];
    if (self.webView.loading) {
        toolbarItems[0] = self.stopLoadingButton;
    } else {
        toolbarItems[0] = self.reloadButton;
    }
    self.toolbarItems = [toolbarItems copy];
}

- (void)finishLoad
{
    [self toggleState];
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
}

#pragma mark - Button actions

- (void)action:(id)sender
{
    NSArray *activityItems;
    if (self.activityItems) {
        activityItems = [self.activityItems arrayByAddingObject:self.URL];
    } else {
        activityItems = @[self.URL];
    }
    
    UIActivityViewController *vc = [[UIActivityViewController alloc] initWithActivityItems:activityItems
                                                                     applicationActivities:self.applicationActivities];
    if (self.excludedActivityTypes) {
        vc.excludedActivityTypes = self.excludedActivityTypes;
    }
    
    [self presentViewController:vc animated:YES completion:NULL];
}

#pragma mark - Web view delegate

- (void)webViewDidStartLoad:(UIWebView *)webView
{
    [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:YES];
    [self toggleState];
}

- (void)webViewDidFinishLoad:(UIWebView *)webView
{
    [self finishLoad];
    self.title = [webView stringByEvaluatingJavaScriptFromString:@"document.title"];
    self.URL = self.webView.request.URL;
}

- (void)webView:(UIWebView *)webView didFailLoadWithError:(NSError *)error
{
    [self finishLoad];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)close:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];    
}

- (void)done:(id)sender
{
    [self.navigationController.presentingViewController dismissViewControllerAnimated:YES completion:nil];
}

@end
