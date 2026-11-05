#import "Patches/AirTrafficControl/AirTrafficControl.h"

static NSString *const DPRoutesKey = @"airTrafficRoutes", *const DPDefaultKey = @"airTrafficDefault";

static NSUserDefaults *DPRouteDefaults(void) {
    static NSUserDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [[NSUserDefaults alloc] initWithSuiteName:@"com.diapatches"]; });
    return defaults;
}

// A route is {url, match, profile}: match is "contains" or "equals". Routes saved before there was a choice were
// {domain, profile}, and read as "contains" that domain.
NSArray<NSDictionary *> *DPRoutes(void) {
    NSMutableArray<NSDictionary *> *routes = [NSMutableArray new];
    for (id route in [DPRouteDefaults() arrayForKey:DPRoutesKey]) {
        if (![route isKindOfClass:NSDictionary.class] || ![route[@"profile"] isKindOfClass:NSString.class]) continue;
        id url = route[@"url"] ?: route[@"domain"];
        if (![url isKindOfClass:NSString.class]) continue;
        NSString *match = [route[@"match"] isEqual:DPMatchEquals] ? DPMatchEquals : DPMatchContains;
        [routes addObject:@{ @"url" : url, @"match" : match, @"profile" : route[@"profile"] }];
    }
    return routes;
}

void DPSetRoutes(NSArray<NSDictionary *> *routes) { [DPRouteDefaults() setObject:routes forKey:DPRoutesKey]; }

NSString *DPDefaultProfile(void) { return [DPRouteDefaults() stringForKey:DPDefaultKey] ?: @""; }

void DPSetDefaultProfile(NSString *profileID) { [DPRouteDefaults() setObject:profileID ?: @"" forKey:DPDefaultKey]; }

// A URL as routes compare it: lowercase, without its scheme, "www.", fragment or a trailing slash. "https://www.YouTube.com/"
// is "youtube.com". The query stays only if `query` says so.
static NSString *DPComparable(NSString *text, BOOL query) {
    NSString *url = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].lowercaseString;
    NSRange scheme = [url rangeOfString:@"://"];
    if (scheme.location != NSNotFound) url = [url substringFromIndex:NSMaxRange(scheme)];
    if ([url hasPrefix:@"www."]) url = [url substringFromIndex:4];
    NSUInteger end = [url rangeOfString:query ? @"#" : @"?"].location;
    if (end == NSNotFound && !query) end = [url rangeOfString:@"#"].location;
    if (end != NSNotFound) url = [url substringToIndex:end];
    while ([url hasSuffix:@"/"]) url = [url substringToIndex:url.length - 1];
    return url;
}

NSString *DPRouteURL(NSString *text) {
    NSString *url = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    for (NSString *prefix in @[ @"https://", @"http://", @"www." ])
        if ([url.lowercaseString hasPrefix:prefix]) url = [url substringFromIndex:prefix.length];
    return url;
}

// Where `pattern` starts a part of `url`: at its start or after a dot or slash, so "x.com" is in "mobile.x.com/home" but
// not in "netflix.com".
static BOOL DPContainsPart(NSString *url, NSString *pattern) {
    NSRange search = NSMakeRange(0, url.length);
    for (NSRange found; (found = [url rangeOfString:pattern options:0 range:search]).location != NSNotFound;) {
        if (found.location == 0 || [@"./" containsString:[url substringWithRange:NSMakeRange(found.location - 1, 1)]]) return YES;
        search = NSMakeRange(found.location + 1, url.length - found.location - 1);
    }
    return NO;
}

// "Contains" looks at the address and path, and at the query only when the route has one, so a search for "youtube.com"
// on Google isn't sent to YouTube's profile. "Is equal to" compares the whole URL.
static BOOL DPRouteMatches(NSDictionary *route, NSURL *url) {
    BOOL equals = [route[@"match"] isEqual:DPMatchEquals];
    NSString *pattern = DPComparable(route[@"url"], YES);
    if (!pattern.length) return NO;
    NSString *candidate = DPComparable(url.absoluteString, equals || [pattern containsString:@"?"]);
    return equals ? [candidate isEqualToString:pattern] : DPContainsPart(candidate, pattern);
}

// The first route that matches wins, top to bottom. Only web pages are routed: Dia's own pages and other schemes stay put.
NSString *DPRoutedProfile(NSURL *url) {
    if (!url.scheme || ![@[ @"http", @"https" ] containsObject:url.scheme.lowercaseString]) return nil;
    for (NSDictionary *route in DPRoutes())
        if (DPRouteMatches(route, url)) return route[@"profile"];
    return nil;
}
