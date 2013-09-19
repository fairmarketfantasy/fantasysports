//
//  FFTickerDrawerViewController.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTickerDrawerViewController.h"

@interface FFTickerDrawerViewController ()

@end

@implementation FFTickerDrawerViewController

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
}

- (void)getTicker:(SBSuccessBlock)onSuccess failure:(SBErrorBlock)fail
{
    [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/mine" paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {

          if (![JSON[@"data"] count]) {
              // there were no results from mine, so get the public one
              [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/public" paramters:@{} success:
               ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {

               } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
                   NSLog(@"failed to get ticker 2: %@ %@", error, JSON);
               }];
          } else {
              
          }
      } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
          NSLog(@"failed to get ticker: %@ %@", error, JSON);
      }];
}

@end
