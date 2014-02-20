//
//  FFTickerDataSource.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/28/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "FFSession.h"

@class FFTickerDataSource;

@protocol FFTickerDataSourceDelegate <NSObject>

- (void)tickerShowLoading:(FFTickerDataSource*)source;
- (void)ticker:(FFTickerDataSource*)ticker showError:(NSString*)err;
- (void)tickerGotData:(FFTickerDataSource*)ticker;

@end

@interface FFTickerDataSource : NSObject

@property(nonatomic) FFSession* session;
@property(nonatomic) NSArray* tickerData;
@property(nonatomic) NSDate* lastFetch;

- (void)addDelegate:(NSObject<FFTickerDataSourceDelegate>*)delegate;
- (void)removeDelete:(NSObject<FFTickerDataSourceDelegate>*)delegate;

- (void)refresh;

@end
