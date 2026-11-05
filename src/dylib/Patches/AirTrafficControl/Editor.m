// The Routes group on the Settings page, laid out like Arc's: a New Route button, then for each route a URL line (its
// condition, the URL and a remove button) and an Open in line with the profile. Saved as they change.
#import "Patches/AirTrafficControl/AirTrafficControl.h"

// A label like Arc's: a symbol and a word, grey, right-aligned against the controls.
static NSView *DPRouteLabel(NSString *symbol, NSString *text) {
    NSImageView *icon = [NSImageView imageViewWithImage:[NSImage imageWithSystemSymbolName:symbol accessibilityDescription:nil]];
    icon.contentTintColor = NSColor.secondaryLabelColor;
    icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular];
    NSTextField *label = [NSTextField labelWithString:text];
    label.font = [NSFont systemFontOfSize:13];
    label.textColor = NSColor.secondaryLabelColor;
    NSStackView *stack = [NSStackView stackViewWithViews:@[ icon, label ]];
    stack.spacing = 5;
    return stack;
}

@implementation DPRoutesView {
    NSMutableArray<NSTextField *> *_fields;
}

- (instancetype)init {
    if (!(self = [super initWithFrame:NSZeroRect])) return nil;
    self.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.alignment = NSLayoutAttributeLeading;
    self.spacing = 16;
    self.identifier = @"Routes";
    [self reload];
    return self;
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    if (self.window) [self reload];  // Profiles may have come or gone since the page was built.
}

- (void)addRow:(NSView *)row {
    [self addArrangedSubview:row];
    [row.widthAnchor constraintEqualToAnchor:self.widthAnchor].active = YES;
}

- (NSArray<NSArray<NSView *> *> *)linesForRoute:(NSDictionary *)route at:(NSUInteger)index {
    BOOL on = DPAirTrafficControl.on;
    NSPopUpButton *condition = [NSPopUpButton new];
    [condition.menu addItemWithTitle:@"Contains" action:NULL keyEquivalent:@""].representedObject = DPMatchContains;
    [condition.menu addItemWithTitle:@"Is equal to" action:NULL keyEquivalent:@""].representedObject = DPMatchEquals;
    [condition selectItemAtIndex:[condition indexOfItemWithRepresentedObject:route[@"match"]]];
    NSTextField *url = [NSTextField textFieldWithString:route[@"url"]];
    url.placeholderString = @"youtube.com";
    url.bezelStyle = NSTextFieldRoundedBezel;
    url.delegate = self;
    [url setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [_fields addObject:url];
    NSButton *remove = [NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"minus.circle.fill" accessibilityDescription:@"Remove Route"]
                                          target:self action:@selector(remove:)];
    remove.bordered = NO;
    remove.contentTintColor = NSColor.secondaryLabelColor;
    NSPopUpButton *profile = DPProfilePicker(nil, route[@"profile"], self, @selector(pick:));
    profile.controlSize = NSControlSizeRegular;
    profile.font = [NSFont systemFontOfSize:13];
    for (NSControl *control in @[ condition, url, remove, profile ]) {
        control.tag = index;
        control.enabled = on;
    }
    condition.target = self;
    condition.action = @selector(condition:);
    return @[ @[ DPRouteLabel(@"link", @"URL"), condition, url, remove ],
              @[ DPRouteLabel(@"arrow.turn.down.right", @"Open in"), profile, NSGridCell.emptyContentView, NSGridCell.emptyContentView ] ];
}

- (void)reload {
    for (NSView *view in self.arrangedSubviews.copy) {
        [self removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    _fields = [NSMutableArray new];
    BOOL ready = DPProfiles().count >= 2;
    NSTextField *lead = DPNote(ready ? @"A routed site opens in its profile wherever its link is clicked, switching to it if it has to."
                                     : @"Air Traffic Control needs two or more profiles. Add them in Settings › Profiles.");
    NSButton *add = [NSButton buttonWithTitle:@"New Route" target:self action:@selector(add)];
    add.hidden = !ready;
    add.enabled = DPAirTrafficControl.on;
    NSStackView *head = [NSStackView stackViewWithViews:@[ lead, add ]];
    head.spacing = 12;
    head.alignment = NSLayoutAttributeCenterY;
    [self addRow:head];
    NSArray<NSDictionary *> *routes = DPRoutes();
    if (!ready || !routes.count) return;
    NSMutableArray<NSArray<NSView *> *> *lines = [NSMutableArray new];
    [routes enumerateObjectsUsingBlock:^(NSDictionary *route, NSUInteger index, BOOL *_) {
        [lines addObjectsFromArray:[self linesForRoute:route at:index]];
    }];
    NSGridView *grid = [NSGridView gridViewWithViews:lines];
    grid.rowSpacing = 8;
    grid.columnSpacing = 8;
    grid.rowAlignment = NSGridRowAlignmentFirstBaseline;
    // Every column but the URL's has a set width and the URL's fills the rest, so there's one layout to find. Left to
    // the grid, the room went to any column, and the profile menu came out as wide as the URL line only some of the time.
    CGFloat labels = 0, buttons = 0;
    for (NSUInteger row = 0; row < lines.count; row += 2) {
        labels = MAX(labels, MAX(lines[row][0].fittingSize.width, lines[row + 1][0].fittingSize.width));
        buttons = MAX(buttons, lines[row][3].fittingSize.width);
    }
    [grid columnAtIndex:0].width = ceil(labels);
    [grid columnAtIndex:1].width = 150;
    [grid columnAtIndex:3].width = ceil(buttons);
    grid.xPlacement = NSGridCellPlacementFill;
    [grid columnAtIndex:0].xPlacement = NSGridCellPlacementTrailing;
    [grid columnAtIndex:3].xPlacement = NSGridCellPlacementCenter;
    for (NSUInteger index = 0; index < routes.count; index++) {
        [[grid rowAtIndex:index * 2 + 1] mergeCellsInRange:NSMakeRange(1, 2)];  // The profile spans the condition and the URL.
        if (index) [grid rowAtIndex:index * 2].topPadding = 12;
    }
    [self addRow:grid];
}

- (void)add {
    DPSetRoutes([DPRoutes() arrayByAddingObject:@{ @"url" : @"", @"match" : DPMatchContains, @"profile" : DPProfiles().firstObject[@"id"] ?: @"" }]);
    [self reload];
    [self.window makeFirstResponder:_fields.lastObject];
}

- (void)change:(NSUInteger)index with:(void (^)(NSMutableDictionary *route))change {
    NSMutableArray<NSDictionary *> *routes = [DPRoutes() mutableCopy];
    if (index >= routes.count) return;
    NSMutableDictionary *route = [routes[index] mutableCopy];
    change(route);
    routes[index] = route;
    DPSetRoutes(routes);
}

// Saved as typed, so nothing is lost when the window closes, and tidied once editing ends.
- (void)controlTextDidChange:(NSNotification *)note {
    NSTextField *field = note.object;
    [self change:field.tag with:^(NSMutableDictionary *route) { route[@"url"] = field.stringValue; }];
}

- (void)controlTextDidEndEditing:(NSNotification *)note {
    NSTextField *field = note.object;
    NSString *url = DPRouteURL(field.stringValue);
    field.stringValue = url;
    [self change:field.tag with:^(NSMutableDictionary *route) { route[@"url"] = url; }];
}

- (void)condition:(NSPopUpButton *)menu {
    NSString *match = menu.selectedItem.representedObject;
    [self change:menu.tag with:^(NSMutableDictionary *route) { route[@"match"] = match; }];
}

- (void)pick:(NSPopUpButton *)picker {
    NSString *profileID = picker.selectedItem.representedObject;
    if (profileID.length) [self change:picker.tag with:^(NSMutableDictionary *route) { route[@"profile"] = profileID; }];
}

- (void)remove:(NSButton *)button {
    NSMutableArray<NSDictionary *> *routes = [DPRoutes() mutableCopy];
    if ((NSUInteger)button.tag < routes.count) [routes removeObjectAtIndex:button.tag];
    DPSetRoutes(routes);
    [self reload];
}
@end
