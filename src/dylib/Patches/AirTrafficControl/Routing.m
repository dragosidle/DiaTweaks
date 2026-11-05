#import "Patches/AirTrafficControl/AirTrafficControl.h"
#import <objc/message.h>
#import <os/log.h>

enum { DPIgnoreAction = 0 };  // ArcWebContentsNavigationDisposition

static NSMutableSet<NSString *> *DPHandedOver;  // URLs on their way back through Dia after a switch, which the hook lets by.

// With the developer tools on, every decision is logged: log stream --predicate 'eventMessage CONTAINS "DiaPatches ATC"'
static BOOL DPTracing(void) {
    static BOOL on;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ on = [[[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"] boolForKey:@"devTools"]; });
    return on;
}
#define DPTrace(format, ...) do { if (DPTracing()) os_log(OS_LOG_DEFAULT, "DiaPatches ATC: " format, ##__VA_ARGS__); } while (0)

BOOL DPRoutingReady(void) { return DPAirTrafficControl.on && DPProfiles().count >= 2; }

static BOOL DPProfileExists(NSString *profileID) {
    for (NSDictionary *profile in DPProfiles()) if ([profile[@"id"] isEqualToString:profileID]) return YES;
    return NO;
}

// Where `url` goes: its route's profile, the default for a link from another app, or nil to leave it to Dia. A link on
// a page already in the routed domain stays, so moving about a site opened on purpose elsewhere doesn't keep jumping.
static NSString *DPDestination(NSURL *url, NSURL *from, BOOL external) {
    if (![url isKindOfClass:NSURL.class]) return nil;
    if (!DPRoutingReady()) {
        DPTrace("%{public}@ stays: %{public}s", url, DPAirTrafficControl.on ? "fewer than two profiles found" : "off");
        return nil;
    }
    NSString *profile = DPRoutedProfile(url);
    if (!profile && external) profile = DPDefaultProfile();
    if (!profile.length) {
        DPTrace("%{public}@ stays: no route", url);
        return nil;
    }
    if (!DPProfileExists(profile)) {
        DPTrace("%{public}@ stays: its profile %{public}@ is gone", url, profile);
        return nil;
    }
    if (!external && [DPRoutedProfile(from) isEqualToString:profile]) {
        DPTrace("%{public}@ stays: the page %{public}@ is already in that domain", url, from);
        return nil;
    }
    NSWindow *window = NSApp.keyWindow ?: NSApp.orderedWindows.firstObject;
    NSString *current = DPWindowProfile(window);
    if ([current isEqualToString:profile]) {
        DPTrace("%{public}@ stays: the window is on %{public}@ already", url, profile);
        return nil;
    }
    DPTrace("%{public}@ goes to profile %{public}@ (the window shows %{public}@)", url, profile, current ?: @"no profile");
    return profile;
}

// Dia opens links from other apps in the front window's profile, so once a window shows the right one, the link takes that road.
static void DPHandOver(NSURL *url) {
    [DPHandedOver addObject:url.absoluteString];
    SEL open = @selector(application:openURLs:);
    if ([NSApp.delegate respondsToSelector:open]) ((void (*)(id, SEL, id, NSArray *))objc_msgSend)(NSApp.delegate, open, NSApp, @[ url ]);
    else [NSWorkspace.sharedWorkspace openURL:url];
}

void DPOpenInProfile(NSURL *url, NSString *profileID) {
    NSWindow *window = DPWindowOnProfile(profileID);
    for (NSWindow *candidate in NSApp.orderedWindows) if (!window && DPWindowProfile(candidate)) window = candidate;
    if (!window) {
        DPTrace("no browser window to switch, handing %{public}@ to Dia", url);
        return DPHandOver(url);
    }
    DPTrace("switching \"%{public}@\" (on %{public}@) to %{public}@", window.title, DPWindowProfile(window) ?: @"no profile", profileID);
    [NSApp activateIgnoringOtherApps:YES];
    [window makeKeyAndOrderFront:nil];
    DPSwitchToProfile(window, profileID, ^(BOOL switched) {
        if (!switched) os_log(OS_LOG_DEFAULT, "DiaPatches: couldn't switch to profile %{public}@ for %{public}@", profileID, url);
        DPTrace("%{public}s, handing %{public}@ to Dia", switched ? "switched" : "not switched", url);
        DPHandOver(url);
    });
}

static void DPApp_openURLs(id self, SEL _cmd, NSApplication *app, NSArray<NSURL *> *urls) {
    DPTrace("from outside: %{public}@", urls);
    NSMutableArray<NSURL *> *rest = [NSMutableArray new];
    for (NSURL *url in urls) {
        if ([DPHandedOver containsObject:url.absoluteString]) {
            [DPHandedOver removeObject:url.absoluteString];
            [rest addObject:url];
            continue;
        }
        NSString *profile = DPDestination(url, nil, YES);
        if (profile) DPOpenInProfile(url, profile);
        else [rest addObject:url];
    }
    if (rest.count) DPCallOriginal(DPApp_openURLs, self, app, rest);
}

static NSURL *DPPageURL(id webContents) {
    id url = [webContents valueForKey:@"url"];
    return [url isKindOfClass:NSURL.class] ? url : nil;
}

// A link that would load in its own tab. Later, so Dia finishes with the click before the window switches under it.
static NSInteger DPWebContent_decidePolicy(id self, SEL _cmd, id webContents, id action) {
    NSURL *url = [action valueForKey:@"url"];
    DPTrace("navigation %{public}@ disposition %{public}@ on %{public}@", url, [action valueForKey:@"navigationDisposition"], DPPageURL(webContents));
    NSString *profile = DPDestination(url, DPPageURL(webContents), NO);
    if (!profile) return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenInProfile(url, profile); });
    return DPIgnoreAction;
}

// A link that would open a new tab or window. The page Dia made for it is let go the way Peek does, with the action ignored.
static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    DPTrace("new page for %{public}@ disposition %ld on %{public}@", url, (long)disposition, DPPageURL(webContents));
    NSString *profile = DPDestination(url, DPPageURL(webContents), NO);
    if (!profile) return (void)DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, (NSInteger)DPIgnoreAction);
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenInProfile(url, profile); });
}

void DPInstallRouting(void) {
    DPHandedOver = [NSMutableSet new];
    // Links that launched Dia arrive before it has finished launching, so the delegate is hooked as soon as it's there.
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *_) {
        BOOL hookable = [NSApp.delegate respondsToSelector:@selector(application:openURLs:)];
        if (hookable) DPHookClass(object_getClass(NSApp.delegate), @selector(application:openURLs:), (IMP)DPApp_openURLs);
        DPTrace("app delegate %{public}s %{public}s application:openURLs:", object_getClassName(NSApp.delegate), hookable ? "has" : "lacks");
    }];
    DPOnLaunch(^{
        DPTrace("%{public}s %{public}s", DPDiaWebContent, objc_getClass(DPDiaWebContent) ? "found" : "missing, so clicks in pages aren't seen");
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPWebContent_decidePolicy);
        DPHook(DPDiaWebContent, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate);
    });
}

NSString *DPVerifyRouting(DPPatch *patch) {
    if (!patch->on) return nil;
    if (![NSApp.delegate respondsToSelector:@selector(application:openURLs:)]) return @"links from other apps don't reach the router";
    if (!class_getInstanceMethod(objc_getClass(DPDiaWebContent), @selector(webContents:decidePolicyForNavigationAction:))) return @"link clicks don't reach the router";
    if (!DPProfiles().count) return @"can't read the profiles from the switcher";
    return nil;
}
