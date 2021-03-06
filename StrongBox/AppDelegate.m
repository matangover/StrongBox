//
//  AppDelegate.m
//  StrongBox
//
//  Created by Mark McGuill on 03/06/2014.
//  Copyright (c) 2014 Mark McGuill. All rights reserved.
//

#import "AppDelegate.h"
#import "RecordView.h"
#import "BrowseSafeView.h"
#import "PasswordHistoryViewController.h"
#import "PreviousPasswordsTableViewController.h"
#import "real-secrets.h"
#import "ObjectiveDropboxOfficial/ObjectiveDropboxOfficial.h"
#import "GoogleDriveManager.h"
#import "Settings.h"
#import "InitialViewController.h"
#import "SafesViewController.h"
#import "QuickLaunchViewController.h"
#import "StorageBrowserTableViewController.h"
#import "UpgradeViewController.h"
#import "OfflineDetector.h"

@interface AppDelegate ()

@property (nonatomic, strong) NSDate *enterBackgroundTime;
@property (nonatomic, strong) UIViewController *lockView;

@end

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self migrateUserDefaultsToAppGroup]; // iOS Credentials Extension needs access to user settings/safes etc... migrate

    [self initializeDropbox];

    [OfflineDetector.sharedInstance startMonitoringConnectivitity];

    [[Settings sharedInstance] incrementLaunchCount];

    if(Settings.sharedInstance.installDate == nil) {
        Settings.sharedInstance.installDate = [NSDate date];
    }
 
    return YES;
}

-(void)migrateUserDefaultsToAppGroup {
    NSUserDefaults *userDefaults = NSUserDefaults.standardUserDefaults;
    
    NSUserDefaults *groupDefaults = [[NSUserDefaults alloc] initWithSuiteName:kAppGroupName];
    
    static NSString* kDidMigrateSafesToAppGroups = @"DidMigrateToAppGroups";
    
    if(groupDefaults != nil) {
        if (![groupDefaults boolForKey:kDidMigrateSafesToAppGroups]) {
            for(NSString *key in [[userDefaults dictionaryRepresentation] allKeys]) {
                NSLog(@"Migrating Setting: %@", key);
                [groupDefaults setObject:[userDefaults objectForKey:key] forKey:key];
            }
            
            [groupDefaults setBool:YES forKey:kDidMigrateSafesToAppGroups];
            [groupDefaults synchronize];
            
            NSLog(@"Successfully migrated defaults");
        }
        else {
            NSLog(@"No need to migrate defaults, already done.");
        }
    }
    else {
        NSLog(@"Unable to create NSUserDefaults with given app group");
    }
}

- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url
            options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    NSLog(@"openURL: [%@] => [%@]", options, url);
    
    if ([url.absoluteString hasPrefix:@"db"]) {
        DBOAuthResult *authResult = [DBClientsManager handleRedirectURL:url];

        if (authResult != nil) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"isDropboxLinked" object:authResult];
        }

        return YES;
    }
    else if ([url.absoluteString hasPrefix:@"com.googleusercontent.apps"])
    {
        return [[GIDSignIn sharedInstance] handleURL:url
                                   sourceApplication:options[UIApplicationOpenURLOptionsSourceApplicationKey]
                                          annotation:options[UIApplicationOpenURLOptionsAnnotationKey]];
    }
    else {
        InitialViewController *tabController = (InitialViewController *)self.window.rootViewController;

        [tabController importFromUrlOrEmailAttachment:url];

        return YES;
    }

    return NO;
}

- (void)applicationWillResignActive:(UIApplication *)application {
    UITabBarController *tab = (UITabBarController*)self.window.rootViewController;
    UINavigationController *nav = tab.selectedViewController;

    if (![nav.visibleViewController isKindOfClass:[SafesViewController class]] && // Don't show lock screen for these two initial screens as Touch ID/Face ID causes a weird effect of present lock screen while waiting authentication
        ![nav.visibleViewController isKindOfClass:[QuickLaunchViewController class]] &&
        ![nav.visibleViewController isKindOfClass:[UpgradeViewController class]] &&
        ![nav.visibleViewController isKindOfClass:[StorageBrowserTableViewController class]]) // Google Sign In Broken without this... sigh
    {
        self.enterBackgroundTime = [[NSDate alloc] init];

        UIStoryboard *mainStoryboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        self.lockView = [mainStoryboard instantiateViewControllerWithIdentifier:@"LockScreen"];

        [self.lockView.view layoutIfNeeded];
        [tab presentViewController:self.lockView animated:NO completion:nil];
    }
    else {
        self.lockView = nil;
    }
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    if (self.lockView) {
        [self.window.rootViewController dismissViewControllerAnimated:NO completion:nil];
        self.lockView = nil;
    }
    
    if (self.enterBackgroundTime) {
        NSTimeInterval secondsBetween = [[[NSDate alloc]init] timeIntervalSinceDate:self.enterBackgroundTime];
        NSNumber *seconds = [[Settings sharedInstance] getAutoLockTimeoutSeconds];

        if (seconds.longValue != -1  && secondsBetween > seconds.longValue) { // -1 = never
            NSLog(@"Autolock Time [%@s] exceeded, locking safe.", seconds);

            UITabBarController *tabController = (UITabBarController *)self.window.rootViewController;
            UINavigationController* nav = [tabController selectedViewController];
            [nav popToRootViewControllerAnimated:NO];
        }
        
        self.enterBackgroundTime = nil;
    }
}

- (void)initializeDropbox {
    [DBClientsManager setupWithAppKey:DROPBOX_APP_KEY];
}

@end
