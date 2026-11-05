#import "Patches/AirTrafficControl/AirTrafficControl.h"

static NSString *const DPRoutesKey = @"airTrafficRoutes", *const DPDefaultKey = @"airTrafficDefault";

static NSUserDefaults *DPRouteDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return defaults;
}

NSArray<NSDictionary *> *DPRoutes(void) {
    NSMutableArray<NSDictionary *> *routes = [NSMutableArray new];
    for (id route in [DPRouteDefaults() arrayForKey:DPRoutesKey])
        if ([route isKindOfClass:NSDictionary.class] && [route[@"domain"] isKindOfClass:NSString.class] && [route[@"profile"] isKindOfClass:NSString.class])
            [routes addObject:route];
    return routes;
}

void DPSetRoutes(NSArray<NSDictionary *> *routes) { [DPRouteDefaults() setObject:routes forKey:DPRoutesKey]; }

NSString *DPDefaultProfile(void) { return [DPRouteDefaults() stringForKey:DPDefaultKey] ?: @""; }

void DPSetDefaultProfile(NSString *profileID) { [DPRouteDefaults() setObject:profileID ?: @"" forKey:DPDefaultKey]; }

NSString *DPRouteDomain(NSString *text) {
    NSString *domain = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSRange scheme = [domain rangeOfString:@"://"];
    if (scheme.location != NSNotFound) domain = [domain substringFromIndex:NSMaxRange(scheme)];
    NSUInteger end = [domain rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"/?#:@"]].location;
    if (end != NSNotFound) domain = [domain substringToIndex:end];
    if ([domain hasPrefix:@"www."]) domain = [domain substringFromIndex:4];
    return domain;
}

static BOOL DPHostIs(NSString *host, NSString *domain) {
    return domain.length && ([host isEqualToString:domain] || [host hasSuffix:[@"." stringByAppendingString:domain]]);
}

// The first route that matches wins, top to bottom. Only web pages are routed: Dia's own pages and other schemes stay put.
NSString *DPRoutedProfile(NSURL *url) {
    if (!url.scheme || ![@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString]) return nil;
    NSString *host = DPRouteDomain(url.host ?: @"");
    if (!host.length) return nil;
    for (NSDictionary *route in DPRoutes())
        if (DPHostIs(host, DPRouteDomain(route[@"domain"]))) return route[@"profile"];
    return nil;
}
