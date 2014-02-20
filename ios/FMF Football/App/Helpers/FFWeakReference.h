//
//  FFWeakReference.h
//  FMF Football
//
//  Created by Samuel Sutch on 9/28/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface FFWeakReference : NSObject

+ (FFWeakReference*)weakReferenceWithObject:(id)object;

- (id)nonretainedObjectValue;
- (void*)originalObjectValue;

@end