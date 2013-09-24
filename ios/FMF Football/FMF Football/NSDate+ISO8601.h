//
//  NSDate+ISO8601.h
//  CoTap
//
//  Created by Samuel Sutch on 3/11/13.
//  Copyright (c) 2013 CoTap. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDate (ISO8601)

+ dateFromISO8601String:(NSString *)str;

@end
