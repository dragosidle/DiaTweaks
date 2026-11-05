// The hooks that catch links: from other apps through the app delegate, from clicks in pages through Dia's navigation
// policy, from links that open a new tab, and from addresses typed into a tab through its page's navigation controller.
// Redirects are caught in Redirects.m.
#import "Patches/AirTrafficControl/AirTrafficControl.h"
#import <objc/message.h>

enum { DPIgnoreAction = 0 };  // ArcWebContentsNavigationDisposition

static NSMapTable *DPPageByNavigation;  // A page's navigation controller → the page, for the tab a typed address was meant for.

static void DPApp_openURLs(id self, SEL _cmd, NSApplication *app, NSArray<NSURL *> *urls) {
    DPTrace(@"from outside: %@", urls);
    NSMutableArray<NSURL *> *rest = [NSMutableArray new];
    for (NSURL *url in urls) {
        NSString *profile = DPDestination(url, nil, YES);
        if (profile) DPOpenInProfile(url, profile);
        else {
            [rest addObject:url];
            DPNoteFromOutside(url);  // Dia opens it here, but where it redirects to may be routed.
        }
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
    DPTrace(@"navigation %@ disposition %@ on %@", url, [action valueForKey:@"navigationDisposition"], DPPageURL(webContents));
    NSString *profile = DPDestination(url, DPPageURL(webContents), NO);
    if (!profile) {
        DPNoteLoad(webContents, url, DPPageURL(webContents));
        return DPCallOriginal(DPWebContent_decidePolicy, self, webContents, action);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenInProfile(url, profile); });
    return DPIgnoreAction;
}

// A link that would open a new tab or window. The page Dia made for it is let go the way Peek does, with the action ignored.
static void DPWebContent_didCreate(id self, SEL _cmd, id webContents, id newWebContent, NSURL *url, NSInteger disposition) {
    DPTrace(@"new page for %@ disposition %ld on %@", url, (long)disposition, DPPageURL(webContents));
    NSString *profile = DPDestination(url, DPPageURL(webContents), NO);
    if (!profile) {
        DPNoteLoad(newWebContent, url, nil);
        return (void)DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, disposition);
    }
    DPCallOriginal(DPWebContent_didCreate, self, webContents, newWebContent, url, (NSInteger)DPIgnoreAction);
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenInProfile(url, profile); });
}

// An address typed into a tab, or anything else Dia loads into a page itself. The routed one opens elsewhere, and the
// tab Dia made for it, still a blank new tab, closes once that's under way. A tab already on a page keeps it.
static id DPNavigation_load(id self, SEL _cmd, NSURL *url, NSURL *origin) {
    DPTrace(@"load %@ from %@", url, origin);
    NSString *profile = DPDestination(url, nil, NO);
    id page = [DPPageByNavigation objectForKey:self];
    NSURL *current = DPPageURL(page);
    if (!profile) {
        DPNoteLoad(page, url, current);
        return DPCallOriginal(DPNavigation_load, self, url, origin);
    }
    dispatch_async(dispatch_get_main_queue(), ^{ DPOpenInProfile(url, profile); });
    if (page && (!current || [current.scheme isEqualToString:@"dia"]) && [page respondsToSelector:@selector(close)])
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            DPTrace(@"closing the blank tab at %@", current);
            [page performSelector:@selector(close)];
        });
    return nil;
}

// Pages' navigation controllers are hooked by the class of the first one seen, whatever Dia calls it.
static void DPHookNavigation(id webContents) {
    id navigation = nil;
    @try { navigation = [webContents valueForKey:@"navigationController"]; } @catch (NSException *e) {}
    if (!navigation) return DPTrace(@"page %@ has no navigationController", webContents);
    if (!DPPageByNavigation) DPPageByNavigation = [NSMapTable weakToWeakObjectsMapTable];
    [DPPageByNavigation setObject:webContents forKey:navigation];
    DPHookClass(object_getClass(navigation), @selector(load:initiatorOrigin:), (IMP)DPNavigation_load);
}

static id DPBrowser_createWebContents(id self, SEL _cmd, id params) {
    id webContents = DPCallOriginal(DPBrowser_createWebContents, self, params);
    DPHookNavigation(webContents);
    return webContents;
}

static void DPBrowser_didRestore(id self, SEL _cmd, id browser, id webContents, id session) {
    DPCallOriginal(DPBrowser_didRestore, self, browser, webContents, session);
    DPHookNavigation(webContents);
}

void DPInstallRouting(void) {
    DPHook(DPDiaBrowser, @selector(createWebContents:), (IMP)DPBrowser_createWebContents);
    DPHook(DPDiaBrowserDelegate, @selector(browser:didRestoreWebContents:withSessionId:), (IMP)DPBrowser_didRestore);
    // Links that launched Dia arrive before it has finished launching, so the delegate is hooked as soon as it's there.
    [NSNotificationCenter.defaultCenter addObserverForName:NSApplicationWillFinishLaunchingNotification object:nil queue:nil usingBlock:^(NSNotification *_) {
        BOOL hookable = [NSApp.delegate respondsToSelector:@selector(application:openURLs:)];
        if (hookable) DPHookClass(object_getClass(NSApp.delegate), @selector(application:openURLs:), (IMP)DPApp_openURLs);
        DPTrace(@"app delegate %s %@ application:openURLs:", object_getClassName(NSApp.delegate), hookable ? @"has" : @"lacks");
    }];
    DPOnLaunch(^{
        DPTrace(@"%s %@", DPDiaWebContent, objc_getClass(DPDiaWebContent) ? @"found" : @"missing, so clicks in pages aren't seen");
        DPHook(DPDiaWebContent, @selector(webContents:decidePolicyForNavigationAction:), (IMP)DPWebContent_decidePolicy);
        DPHook(DPDiaWebContent, @selector(webContents:didCreateNewWebContent:targetURL:disposition:), (IMP)DPWebContent_didCreate);
        DPInstallRedirects();
    });
}

NSString *DPVerifyRouting(DPPatch *patch) {
    if (!patch->on) return nil;
    if (![NSApp.delegate respondsToSelector:@selector(application:openURLs:)]) return @"links from other apps don't reach the router";
    if (!class_getInstanceMethod(objc_getClass(DPDiaWebContent), @selector(webContents:decidePolicyForNavigationAction:))) return @"link clicks don't reach the router";
    if (!DPProfiles().count) return @"can't read the profiles from the switcher";
    return nil;
}
