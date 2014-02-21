//
//  FFWeakReference.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/28/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFWeakReference.h"

@interface FFWeakReference () {
    __weak id nonretainedObjectValue;
    __unsafe_unretained id originalObjectValue;
}

@end

@implementation FFWeakReference

- (id)initWithObject:(id)object
{
    if (self = [super init]) {
        nonretainedObjectValue = originalObjectValue = object;
    }
    return self;
}

+ (FFWeakReference*)weakReferenceWithObject:(id)object
{
    return [[self alloc] initWithObject:object];
}

- (id)nonretainedObjectValue
{
    return nonretainedObjectValue;
}

- (void*)originalObjectValue
{
    return (__bridge void*)originalObjectValue;
}

// To work appropriately with NSSet
- (BOOL)isEqual:(FFWeakReference*)object
{
    if (![object isKindOfClass:[FFWeakReference class]]) {
        return NO;
    }
    return object.originalObjectValue == self.originalObjectValue;
}

@end
