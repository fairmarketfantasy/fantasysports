//
//  NSDate+ISO8601.m
//  CoTap
//
//  Created by Samuel Sutch on 3/11/13.
//  Copyright (c) 2013 CoTap. All rights reserved.
//

#import "NSDate+ISO8601.h"
#import <time.h>
#include <xlocale.h>

// this taken from AFIncrementalStore repo:
// https://github.com/AFNetworking/AFIncrementalStore/blob/master/AFIncrementalStore/AFRESTClient.m

#define AF_ISO8601_MAX_LENGTH 25

// Adopted from SSToolkit NSDate+SSToolkitAdditions
// Created by Sam Soffes
// Copyright (c) 2008-2012 Sam Soffes
// https://github.com/soffes/sstoolkit/
NSDate * AFDateFromISO8601String(NSString *ISO8601String) {
    if (!ISO8601String) {
        return nil;
    }
    
    const char *str = [ISO8601String cStringUsingEncoding:NSUTF8StringEncoding];
    char newStr[AF_ISO8601_MAX_LENGTH];
    bzero(newStr, AF_ISO8601_MAX_LENGTH);
    
    size_t len = strlen(str);
    if (len == 0) {
        return nil;
    }
    
    // UTC dates ending with Z
    if (len == 20 && str[len - 1] == 'Z') {
        memcpy(newStr, str, len - 1);
        strncpy(newStr + len - 1, "+0000\0", 6);
    }
    
    // Timezone includes a semicolon (not supported by strptime)
    else if (len == 25 && str[22] == ':') {
        memcpy(newStr, str, 22);
        memcpy(newStr + 22, str + 23, 2);
    }
    
    // Fallback: date was already well-formatted OR any other case (bad-formatted)
    else {
        memcpy(newStr, str, len > AF_ISO8601_MAX_LENGTH - 1 ? AF_ISO8601_MAX_LENGTH - 1 : len);
    }
    
    // Add null terminator
    newStr[sizeof(newStr) - 1] = 0;
    
    struct tm tm = {
        .tm_sec = 0,
        .tm_min = 0,
        .tm_hour = 0,
        .tm_mday = 0,
        .tm_mon = 0,
        .tm_year = 0,
        .tm_wday = 0,
        .tm_yday = 0,
        .tm_isdst = -1,
    };
    
    strptime_l(newStr, "%FT%T%z", &tm, NULL);
    
    return [NSDate dateWithTimeIntervalSince1970:mktime(&tm)];
}

@implementation NSDate (ISO8601)

+ (id)dateFromISO8601String:(NSString *)str
{
    return AFDateFromISO8601String(str);
}

@end
