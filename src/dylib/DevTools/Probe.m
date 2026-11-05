// Answers a script's questions about Dia's objects, for finding what a patch can hook or read:
//     com.diapatches.dev.probe, object "ArcBrowser,app,_TtC10TabSidebar17SpaceSwitcherView.itemViews"
// Each name is a class, `app` for the app delegate's class, or a class followed by Swift fields to read from its first
// view on screen. For each, probe.txt beside the dylib gets the value's class and description, then every instance
// variable and method up the class chain. The menu bar goes at the end, with each item's shortcut, action and target.
// scripts/probe sends it and prints the answer.
#import "DevTools/DevTools.h"
#include <dlfcn.h>

@interface NSObject (DPProbeSwiftFields)
- (id)safeSwiftValueForKey:(NSString *)key;  // AXCoreUtilities, in every AppKit app: reads Swift properties the Obj-C runtime hides.
@end

static void DPDescribeClass(Class cls, NSMutableString *out) {
    NSArray<Class> *roots = @[ NSObject.class, NSView.class, NSResponder.class, NSViewController.class, NSWindowController.class ];
    for (; cls && ![roots containsObject:cls]; cls = class_getSuperclass(cls)) {
        [out appendFormat:@"== %s\n", class_getName(cls)];
        unsigned count = 0;
        Ivar *ivars = class_copyIvarList(cls, &count);
        for (unsigned i = 0; i < count; i++) [out appendFormat:@"  ivar %s %s\n", ivar_getName(ivars[i]), ivar_getTypeEncoding(ivars[i]) ?: ""];
        free(ivars);
        Method *methods = class_copyMethodList(cls, &count);
        for (unsigned i = 0; i < count; i++) [out appendFormat:@"  -%s %s\n", sel_getName(method_getName(methods[i])), method_getTypeEncoding(methods[i])];
        free(methods);
        methods = class_copyMethodList(object_getClass(cls), &count);
        for (unsigned i = 0; i < count; i++) [out appendFormat:@"  +%s\n", sel_getName(method_getName(methods[i]))];
        free(methods);
    }
}

static void DPProbe(NSString *spec, NSMutableString *out) {
    NSArray<NSString *> *parts = [spec componentsSeparatedByString:@"."];
    NSString *name = parts.firstObject;
    id object = [name isEqualToString:@"app"] ? NSApp.delegate : DPFindViews(name.UTF8String).firstObject;
    Class cls = object ? object_getClass(object) : NSClassFromString(name);
    [out appendFormat:@"\n#### %@: %s, %@\n", spec, cls ? class_getName(cls) : "no such class", object ? @"live" : @"no live one"];
    for (NSString *key in [parts subarrayWithRange:NSMakeRange(1, parts.count - 1)]) {
        id value = nil;
        @try { value = [object safeSwiftValueForKey:key]; } @catch (NSException *e) {}
        if (!value) @try { value = [object valueForKey:key]; } @catch (NSException *e) {}
        if (!value) return (void)[out appendFormat:@"%@: nil\n", key];
        object = value;
        cls = object_getClass(object);
        NSString *description = [object description] ?: @"";
        if (description.length > 3000) description = [[description substringToIndex:3000] stringByAppendingString:@"…"];
        [out appendFormat:@"%@: %s\n%@\n", key, class_getName(cls), description];
    }
    DPDescribeClass(cls, out);
}

static void DPDescribeMenu(NSMenu *menu, NSUInteger depth, NSMutableString *out) {
    for (NSMenuItem *item in menu.itemArray) {
        [out appendFormat:@"%*s%@", (int)depth * 2, "", item.isSeparatorItem ? @"-" : item.title];
        if (item.keyEquivalent.length) [out appendFormat:@" [%@ %lu]", item.keyEquivalent, (unsigned long)item.keyEquivalentModifierMask];
        if (item.action) [out appendFormat:@" %@ -> %s", NSStringFromSelector(item.action), item.target ? object_getClassName(item.target) : "nil"];
        [out appendString:@"\n"];
        if (item.submenu) DPDescribeMenu(item.submenu, depth + 1, out);
    }
}

void DPListenForProbes(void) {
    [NSDistributedNotificationCenter.defaultCenter addObserverForName:@"com.diapatches.dev.probe" object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
        NSMutableString *out = [NSMutableString new];
        for (NSString *spec in [[note.object description] componentsSeparatedByString:@","]) if (spec.length) DPProbe(spec, out);
        [out appendString:@"\n#### menus\n"];
        DPDescribeMenu(NSApp.mainMenu, 0, out);
        Dl_info dylib;
        dladdr((const void *)DPListenForProbes, &dylib);
        [out writeToFile:[@(dylib.dli_fname).stringByDeletingLastPathComponent stringByAppendingPathComponent:@"probe.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }];
}
