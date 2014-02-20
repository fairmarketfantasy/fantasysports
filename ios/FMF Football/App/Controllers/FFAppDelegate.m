//
//  FFAppDelegate.m
//  FMF Football
//
//  Created by Samuel Sutch on 9/10/13.
//  Copyright (c) 2013 FairMarketFantasy. All rights reserved.
//

#import "FFAppDelegate.h"
#import <SBData/SBModel.h>
#import "FFStyle.h"
#import <FacebookSDK/FacebookSDK.h>
#import "FFSession.h"

@implementation FFAppDelegate

- (BOOL)application:(UIApplication*)application
    didFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    [SBModelMeta initDb];
    [FFStyle customizeAppearance];
    [[Ubertesters shared] initialize];
    return YES;
}

- (BOOL)application:(UIApplication*)application
              openURL:(NSURL*)url
    sourceApplication:(NSString*)sourceApplication
           annotation:(id)annotation
{
    return [FBSession.activeSession handleOpenURL:url];
}

- (void)applicationWillResignActive:(UIApplication*)application
{
    // Sent when the application is about to move from active to inactive state.
    // This can occur for certain types of temporary interruptions (such as an
    // incoming phone call or SMS message) or when the user quits the application
    // and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down
    // OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication*)application
{
    // Use this method to release shared resources, save user data, invalidate
    // timers, and store enough application state information to restore your
    // application to its current state in case it is terminated later.
    // If your application supports background execution, this method is called
    // instead of applicationWillTerminate: when the user quits.
}

- (void)applicationWillEnterForeground:(UIApplication*)application
{
    // Called as part of the transition from the background to the inactive state;
    // here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication*)application
{
    // Restart any tasks that were paused (or not yet started) while the
    // application was inactive. If the application was previously in the
    // background, optionally refresh the user interface.
    [FBSession.activeSession handleDidBecomeActive];
}

- (void)applicationWillTerminate:(UIApplication*)application
{
    // Called when the application is about to terminate. Save data if
    // appropriate. See also applicationDidEnterBackground:.
}

- (void)application:(UIApplication*)app
    didRegisterForRemoteNotificationsWithDeviceToken:(NSData*)devToken
{
    self.pushToken =
        [[[[devToken description] stringByReplacingOccurrencesOfString:@" "
                                                            withString:@""]
             stringByReplacingOccurrencesOfString:@"<"
                                       withString:@""]
            stringByReplacingOccurrencesOfString:@">"
                                      withString:@""];
    NSLog(@"successfully got push token: %@", self.pushToken);
    [[NSNotificationCenter defaultCenter]
        postNotificationName:SBDidReceiveRemoteNotificationAuthorization
                      object:nil
                    userInfo:@{
                                 @"pushToken" : self.pushToken
                             }];
}

- (void)application:(UIApplication*)app
    didFailToRegisterForRemoteNotificationsWithError:(NSError*)err
{
    NSLog(@"Error in push registration. Error: %@", err);
}

- (void)application:(UIApplication*)application
    didReceiveRemoteNotification:(NSDictionary*)userInfo
{
    NSLog(@"did receive push notification %@", userInfo);
    [[NSNotificationCenter defaultCenter]
        postNotificationName:FFDidReceiveRemoteNotification
                      object:nil
                    userInfo:userInfo];
}

@end
