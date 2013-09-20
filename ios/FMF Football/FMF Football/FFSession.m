//
//  FFSession.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/19/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFSession.h"

@implementation FFSession

- (id)deserializeJSON:(id)JSON
{
    if (JSON[@"data"] && [JSON[@"data"] isKindOfClass:[NSArray class]] && [JSON[@"data"] count]) {
        // it's JSONH
        NSArray *lst = JSON[@"data"];
        NSMutableArray *ret = [NSMutableArray array];
        int klength = [lst[0] integerValue];
        int i = 1 + klength;
        while (i < lst.count) {
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            int ki = 0;
            while (ki < klength) {
                ki++;
                d[lst[ki]] = lst[i];
                i++;
            }
            [ret addObject:d];
        }
        return ret;
    }
    return JSON;
}

@end
