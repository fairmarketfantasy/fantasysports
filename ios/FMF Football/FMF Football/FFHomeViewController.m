//
//  FFHomeViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/17/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFHomeViewController.h"
#import "FFSessionViewController.h"

@interface FFHomeViewController ()

@end

@implementation FFHomeViewController

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

    UIView *leftView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 44)];
    UIButton *gmenu = [UIButton buttonWithType:UIButtonTypeCustom];
    [gmenu setImage:[UIImage imageNamed:@"globalmenu.png"] forState:UIControlStateNormal];
    gmenu.frame = CGRectMake(-2, 0, 35, 44);
    [leftView addSubview:gmenu];
    UIImageView *logo = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"fmf-logo.png"]];
    logo.frame = CGRectMake(32, 15, 150, 19);
    [leftView addSubview:logo];
    
    self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:leftView];
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:self.sessionController.balanceView];
}

- (void)viewDidAppear:(BOOL)animated
{
    UIViewController *cont2 = [[UIViewController alloc] init];
    cont2.view.backgroundColor = [UIColor redColor];
    [self showControllerInDrawer:self.sessionController.maximizedTicker
         minimizedViewController:self.sessionController.minimizedTicker
                        animated:NO];
    
    double delayInSeconds = 2.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
//        [self showBanner:@"Hello there" target:nil selector:NULL];

    });
}

@end
