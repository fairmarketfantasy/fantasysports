//
//  FFTickerDataSource.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/28/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFTickerDataSource.h"
#import "FFWeakReference.h"


@interface FFTickerDataSource ()

@property (nonatomic) NSMutableArray *delegates;

- (void)notifyDelegatesLoading;
- (void)notifyDelegatesError:(NSString *)errStr;
- (void)notifyDelegatesGotData;

@end


@implementation FFTickerDataSource

- (id)init
{
    self = [super init];
    if (self) {
        _delegates = [NSMutableArray array];
    }
    return self;
}

- (void)refresh
{
    if (!self.tickerData || !self.tickerData.count) {
        // show loading, haven't gotten anything yet
        [self notifyDelegatesLoading];
    }
    // not logged in yet, so use an anonymous session
    if (!self.session) {
        FFSession *tempSession = [FFSession anonymousSession];
        [tempSession anonymousJSONRequestWithMethod:@"GET" path:@"/players/public" parameters:@{} success:
         ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
             if (![JSON isKindOfClass:[NSArray class]]) {
                 [self notifyDelegatesError:NSLocalizedString(@"Error loading ticker data", nil)];
                 return;
             }
             self.tickerData = JSON;
             self.lastFetch = [NSDate date];
             [self notifyDelegatesGotData];
         } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
             NSLog(@"failed to get public player timeline %@ %@", error, JSON);
             [self notifyDelegatesError:error.userInfo[NSLocalizedDescriptionKey]];
         }];
        return;
    }
    [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/mine" paramters:@{} success:
     ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
         if (![JSON isKindOfClass:[NSArray class]] || ![JSON count]) {
             // there were no results from mine, so get the public one
             [self.session authorizedJSONRequestWithMethod:@"GET" path:@"/players/public" paramters:@{} success:
              ^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, id JSON) {
                  if (![JSON isKindOfClass:[NSArray class]]) {
                      [self notifyDelegatesError:NSLocalizedString(@"Error loading ticker data", nil)];
                      return;
                  }
                  self.tickerData = JSON;
                  self.lastFetch = [NSDate date];
                  [self notifyDelegatesGotData];
              } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
                  NSLog(@"failed to get ticker 2: %@ %@", error, JSON);
                  [self notifyDelegatesError:error.userInfo[NSLocalizedDescriptionKey]];
              }];
         } else {
             self.tickerData = JSON;
             self.lastFetch = [NSDate date];
             [self notifyDelegatesGotData];
         }
     } failure:^(NSURLRequest *request, NSHTTPURLResponse *httpResponse, NSError *error, id JSON) {
         NSLog(@"failed to get ticker: %@ %@", error, JSON);
         [self notifyDelegatesError:error.userInfo[NSLocalizedDescriptionKey]];
     }];
}

- (void)notifyDelegatesLoading
{
    for (FFWeakReference *ref in _delegates) {
        if (ref.nonretainedObjectValue) {
            [ref.nonretainedObjectValue tickerShowLoading:self];
        }
    }
}

- (void)notifyDelegatesError:(NSString *)errStr
{
    for (FFWeakReference *ref in _delegates) {
        if (ref.nonretainedObjectValue) {
            [ref.nonretainedObjectValue ticker:self showError:errStr];
        }
    }
}

- (void)notifyDelegatesGotData
{
    for (FFWeakReference *ref in _delegates) {
        if (ref.nonretainedObjectValue) {
            [ref.nonretainedObjectValue tickerGotData:self];
        }
    }
}

- (void)addDelegate:(NSObject<FFTickerDataSourceDelegate> *)delegate
{
    [_delegates addObject:[FFWeakReference weakReferenceWithObject:delegate]];
}

- (void)removeDelete:(NSObject<FFTickerDataSourceDelegate> *)delegate
{
    [_delegates removeObject:[FFWeakReference weakReferenceWithObject:delegate]];
}

@end
