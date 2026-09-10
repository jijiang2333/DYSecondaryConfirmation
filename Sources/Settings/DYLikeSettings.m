#import "DYLikeSettings.h"
#import "../Core/DYLikeCore.h"
#import <objc/runtime.h>

@interface DYLikeAboutViewController : UIViewController <UITextViewDelegate>
@property(nonatomic, strong) UIView *panel;
@end

static NSString *const DYLikeTelegramURL = @"https://t.me/JiJiang_778";
static NSString *const DYLikeTelegramAppURL = @"tg://resolve?domain=JiJiang_778";

@implementation DYLikeSettingsViewController

- (instancetype)init {
    return [super initWithStyle:UITableViewStyleInsetGrouped];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"二次确认";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.backgroundColor = UIColor.systemGroupedBackgroundColor;
    self.tableView.separatorColor = UIColor.separatorColor;
    self.tableView.rowHeight = UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight = 58;
    self.tableView.sectionHeaderHeight = UITableViewAutomaticDimension;
    self.tableView.sectionFooterHeight = UITableViewAutomaticDimension;
    self.tableView.showsVerticalScrollIndicator = NO;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme)
        name:DYLikeThemeDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self updateTheme];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self updateTheme];
    [self.tableView reloadData];
}

- (void)updateTheme {
    UIUserInterfaceStyle style = DYLikeUserInterfaceStyle();
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
    UITraitCollection *theme = [UITraitCollection traitCollectionWithUserInterfaceStyle:self.overrideUserInterfaceStyle];
    UINavigationBarAppearance *appearance = [UINavigationBarAppearance new];
    [appearance configureWithOpaqueBackground];
    appearance.backgroundColor = [UIColor.systemGroupedBackgroundColor resolvedColorWithTraitCollection:theme];
    appearance.titleTextAttributes = @{NSForegroundColorAttributeName: [UIColor.labelColor resolvedColorWithTraitCollection:theme]};
    self.navigationItem.standardAppearance = appearance;
    self.navigationItem.scrollEdgeAppearance = appearance;
    self.navigationItem.compactAppearance = appearance;
    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    [self updateTheme];
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return DYLikeUserInterfaceStyle() == UIUserInterfaceStyleDark ? UIStatusBarStyleLightContent : UIStatusBarStyleDarkContent;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 3 : 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"功能开关" : @"其他";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"开启后，抖音对应操作会先显示确认弹窗；设置修改后立即生效。";
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 1) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1
                                                        reuseIdentifier:nil];
        cell.textLabel.text = @"关于插件";
        cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        cell.textLabel.textColor = UIColor.labelColor;
        cell.detailTextLabel.text = DYLikeVersion;
        cell.detailTextLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
        cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
        cell.imageView.image = [UIImage systemImageNamed:@"info.circle"
            withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:19
                weight:UIImageSymbolWeightMedium]];
        cell.imageView.tintColor = UIColor.systemBlueColor;
        cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
        cell.textLabel.adjustsFontForContentSizeCategory = YES;
        cell.detailTextLabel.adjustsFontForContentSizeCategory = YES;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        return cell;
    }

    static NSArray<NSString *> *titles;
    static NSArray<NSString *> *symbols;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        titles = @[@"点赞", @"收藏", @"关注"];
        symbols = @[@"heart.fill", @"bookmark.fill", @"person.badge.plus"];
    });

    NSUInteger index = (NSUInteger)indexPath.row;
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault
                                                    reuseIdentifier:nil];
    cell.textLabel.text = titles[index];
    cell.textLabel.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    cell.textLabel.adjustsFontForContentSizeCategory = YES;
    cell.textLabel.textColor = UIColor.labelColor;
    cell.backgroundColor = UIColor.secondarySystemGroupedBackgroundColor;
    cell.imageView.image = [UIImage systemImageNamed:symbols[index]
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:20
            weight:UIImageSymbolWeightMedium]];
    cell.imageView.tintColor = DYLikeAccent((DYLikeActionType)index);
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    UISwitch *toggle = [UISwitch new];
    toggle.onTintColor = DYLikeAccent((DYLikeActionType)index);
    toggle.on = DYLikeEnabled((DYLikeActionType)index);
    toggle.tag = (NSInteger)index;
    toggle.accessibilityLabel = [titles[index] stringByAppendingString:@"二次确认"];
    [toggle addTarget:self action:@selector(toggleChanged:) forControlEvents:UIControlEventValueChanged];
    cell.accessoryView = toggle;
    return cell;
}

- (void)toggleChanged:(UISwitch *)toggle {
    if (toggle.tag < 0 || toggle.tag > 2) return;
    NSArray<NSString *> *keys = @[DYLikeLikeEnabledKey, DYLikeFavoriteEnabledKey, DYLikeFollowEnabledKey];
    [NSUserDefaults.standardUserDefaults setBool:toggle.isOn forKey:keys[(NSUInteger)toggle.tag]];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section != 1) return;

    DYLikeAboutViewController *about = [DYLikeAboutViewController new];
    about.overrideUserInterfaceStyle = DYLikeUserInterfaceStyle();
    about.modalPresentationStyle = UIModalPresentationOverFullScreen;
    about.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:about animated:YES completion:nil];
}

- (void)closeSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end

@implementation DYLikeAboutViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:0.42];

    UIControl *backdrop = [[UIControl alloc] initWithFrame:CGRectZero];
    backdrop.translatesAutoresizingMaskIntoConstraints = NO;
    backdrop.accessibilityLabel = @"关闭关于插件";
    [backdrop addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:backdrop];

    self.panel = [UIView new];
    UIView *panel = self.panel;
    panel.translatesAutoresizingMaskIntoConstraints = NO;
    panel.backgroundColor = UIColor.secondarySystemBackgroundColor;
    panel.layer.cornerRadius = 8;
    panel.layer.cornerCurve = kCACornerCurveContinuous;
    panel.layer.shadowColor = UIColor.blackColor.CGColor;
    panel.layer.shadowOpacity = 0.18;
    panel.layer.shadowRadius = 20;
    panel.layer.shadowOffset = CGSizeMake(0, 8);
    [self.view addSubview:panel];

    UIScrollView *scroll = [UIScrollView new];
    scroll.translatesAutoresizingMaskIntoConstraints = NO;
    scroll.alwaysBounceVertical = NO;
    scroll.clipsToBounds = YES;
    [panel addSubview:scroll];

    UIStackView *stack = [UIStackView new];
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentFill;
    stack.spacing = 16;
    [scroll addSubview:stack];

    UIImageView *icon = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"checkmark.circle.fill"
        withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:32 weight:UIImageSymbolWeightMedium]]];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = UIColor.systemBlueColor;
    icon.isAccessibilityElement = NO;
    [icon.heightAnchor constraintEqualToConstant:42].active = YES;
    [stack addArrangedSubview:icon];

    UILabel *title = [UILabel new];
    title.text = @"关于\nDYSecondaryConfirmation";
    title.textColor = UIColor.labelColor;
    title.textAlignment = NSTextAlignmentCenter;
    title.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleTitle3]
        scaledFontForFont:[UIFont systemFontOfSize:18 weight:UIFontWeightSemibold] maximumPointSize:26];
    title.adjustsFontForContentSizeCategory = YES;
    title.numberOfLines = 0;
    title.lineBreakMode = NSLineBreakByCharWrapping;
    title.accessibilityLabel = @"关于DYSecondaryConfirmation";
    title.accessibilityTraits |= UIAccessibilityTraitHeader;
    [stack addArrangedSubview:title];

    UILabel *(^infoLabel)(NSString *) = ^UILabel *(NSString *text) {
        UILabel *label = [UILabel new];
        label.text = text;
        label.textColor = UIColor.labelColor;
        label.textAlignment = NSTextAlignmentLeft;
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleBody];
        label.adjustsFontForContentSizeCategory = YES;
        label.numberOfLines = 0;
        return label;
    };
    UIStackView *metadata = [[UIStackView alloc] initWithArrangedSubviews:@[
        infoLabel([NSString stringWithFormat:@"作者：%@", DYLikeAuthor]),
        infoLabel([NSString stringWithFormat:@"版本：%@", DYLikeVersion])
    ]];
    metadata.axis = UILayoutConstraintAxisVertical;
    metadata.spacing = 8;
    UITextView *telegram = [UITextView new];
    telegram.backgroundColor = UIColor.clearColor;
    telegram.editable = NO;
    telegram.scrollEnabled = NO;
    telegram.selectable = YES;
    telegram.delegate = self;
    telegram.textContainerInset = UIEdgeInsetsZero;
    telegram.textContainer.lineFragmentPadding = 0;
    telegram.adjustsFontForContentSizeCategory = YES;
    NSString *telegramText = [NSString stringWithFormat:@"Telegram：%@", DYLikeTelegramURL];
    NSMutableAttributedString *telegramAttributed = [[NSMutableAttributedString alloc] initWithString:telegramText attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleBody],
        NSForegroundColorAttributeName: UIColor.labelColor
    }];
    NSRange telegramRange = [telegramText rangeOfString:DYLikeTelegramURL];
    [telegramAttributed addAttribute:NSLinkAttributeName value:[NSURL URLWithString:DYLikeTelegramURL]
                                range:telegramRange];
    telegram.attributedText = telegramAttributed;
    telegram.linkTextAttributes = @{NSForegroundColorAttributeName: UIColor.linkColor};
    telegram.accessibilityLabel = telegramText;
    [telegram.heightAnchor constraintGreaterThanOrEqualToConstant:28].active = YES;
    [metadata addArrangedSubview:telegram];
    [stack addArrangedSubview:metadata];

    UIView *separator = [UIView new];
    separator.backgroundColor = UIColor.separatorColor;
    [separator.heightAnchor constraintEqualToConstant:1.0 / UIScreen.mainScreen.scale].active = YES;
    [stack addArrangedSubview:separator];

    UILabel *repositoryTitle = infoLabel(@"开源仓库");
    repositoryTitle.textColor = UIColor.secondaryLabelColor;
    repositoryTitle.font = [UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    [stack addArrangedSubview:repositoryTitle];
    [stack setCustomSpacing:4 afterView:repositoryTitle];

    UITextView *repository = [UITextView new];
    repository.backgroundColor = UIColor.clearColor;
    repository.editable = NO;
    repository.scrollEnabled = NO;
    repository.selectable = YES;
    repository.delegate = self;
    repository.textContainerInset = UIEdgeInsetsZero;
    repository.textContainer.lineFragmentPadding = 0;
    repository.adjustsFontForContentSizeCategory = YES;
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByCharWrapping;
    paragraph.lineSpacing = 3;
    repository.attributedText = [[NSAttributedString alloc] initWithString:DYLikeRepositoryURL attributes:@{
        NSFontAttributeName: [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline],
        NSLinkAttributeName: [NSURL URLWithString:DYLikeRepositoryURL],
        NSParagraphStyleAttributeName: paragraph
    }];
    repository.linkTextAttributes = @{NSForegroundColorAttributeName: UIColor.linkColor};
    [repository.heightAnchor constraintGreaterThanOrEqualToConstant:44].active = YES;
    [stack addArrangedSubview:repository];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.titleLabel.font = [[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]
        scaledFontForFont:[UIFont systemFontOfSize:16 weight:UIFontWeightSemibold] maximumPointSize:26];
    close.titleLabel.adjustsFontForContentSizeCategory = YES;
    [close setTitle:@"👌" forState:UIControlStateNormal];
    close.accessibilityLabel = @"完成";
    [close setTitleColor:UIColor.labelColor forState:UIControlStateNormal];
    close.backgroundColor = UIColor.tertiarySystemFillColor;
    close.layer.cornerRadius = 8;
    close.contentEdgeInsets = UIEdgeInsetsMake(12, 12, 12, 12);
    [close addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
    [close.heightAnchor constraintGreaterThanOrEqualToConstant:48].active = YES;
    [panel addSubview:close];

    NSLayoutConstraint *preferredWidth = [panel.widthAnchor constraintEqualToConstant:360];
    preferredWidth.priority = 999;
    NSLayoutConstraint *contentHeight = [scroll.heightAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.heightAnchor];
    contentHeight.priority = 750;
    [NSLayoutConstraint activateConstraints:@[
        [backdrop.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [backdrop.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [backdrop.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [backdrop.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [panel.centerXAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerXAnchor],
        [panel.centerYAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.centerYAnchor],
        preferredWidth,
        [panel.widthAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.widthAnchor constant:-40],
        [panel.topAnchor constraintGreaterThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:16],
        [panel.bottomAnchor constraintLessThanOrEqualToAnchor:self.view.safeAreaLayoutGuide.bottomAnchor constant:-16],
        [scroll.topAnchor constraintEqualToAnchor:panel.topAnchor constant:24],
        [scroll.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24],
        [scroll.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24],
        [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:44], contentHeight,
        [stack.topAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.topAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.leadingAnchor],
        [stack.trailingAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.trailingAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:scroll.contentLayoutGuide.bottomAnchor],
        [stack.widthAnchor constraintEqualToAnchor:scroll.frameLayoutGuide.widthAnchor],
        [close.topAnchor constraintEqualToAnchor:scroll.bottomAnchor constant:24],
        [close.leadingAnchor constraintEqualToAnchor:panel.leadingAnchor constant:24],
        [close.trailingAnchor constraintEqualToAnchor:panel.trailingAnchor constant:-24],
        [close.bottomAnchor constraintEqualToAnchor:panel.bottomAnchor constant:-20]
    ]];
    self.view.accessibilityViewIsModal = YES;
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme)
        name:DYLikeThemeDidChangeNotification object:nil];
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(updateTheme)
        name:UIApplicationDidBecomeActiveNotification object:nil];
    [self updateTheme];
}

- (void)updateTheme {
    UIUserInterfaceStyle style = DYLikeUserInterfaceStyle();
    if (self.overrideUserInterfaceStyle != style) self.overrideUserInterfaceStyle = style;
    BOOL dark = self.overrideUserInterfaceStyle == UIUserInterfaceStyleDark;
    self.view.backgroundColor = [UIColor colorWithWhite:0 alpha:dark ? 0.58 : 0.36];
    self.panel.layer.shadowOpacity = dark ? 0.32 : 0.16;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (self.isViewLoaded) [self updateTheme];
}

- (BOOL)textView:(UITextView *)textView shouldInteractWithURL:(NSURL *)url
        inRange:(NSRange)characterRange interaction:(UITextItemInteraction)interaction {
    if ([url.absoluteString isEqualToString:DYLikeTelegramURL]) {
        NSURL *telegramAppURL = [NSURL URLWithString:DYLikeTelegramAppURL];
        NSURL *fallbackURL = [NSURL URLWithString:DYLikeTelegramURL];
        [UIApplication.sharedApplication openURL:telegramAppURL options:@{}
                                completionHandler:^(BOOL opened) {
            if (!opened) [UIApplication.sharedApplication openURL:fallbackURL options:@{} completionHandler:nil];
        }];
    } else if ([url.absoluteString isEqualToString:DYLikeRepositoryURL]) {
        [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
    return NO;
}

- (void)dealloc {
    [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)close {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)accessibilityPerformEscape {
    [self close];
    return YES;
}

@end

static UIViewController *DYLikeTop(UIViewController *controller) {
    if (controller.presentedViewController && !controller.presentedViewController.isBeingDismissed) {
        return DYLikeTop(controller.presentedViewController);
    }
    if ([controller isKindOfClass:UINavigationController.class]) {
        return DYLikeTop(((UINavigationController *)controller).visibleViewController);
    }
    if ([controller isKindOfClass:UITabBarController.class]) {
        return DYLikeTop(((UITabBarController *)controller).selectedViewController);
    }
    return controller;
}

void DYLikeOpenSettings(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = DYLikeActiveWindow();
        UIViewController *top = DYLikeTop(window.rootViewController);
        if (!top || [top isKindOfClass:DYLikeSettingsViewController.class] ||
            [top isKindOfClass:DYLikeAboutViewController.class]) return;

        DYLikeSettingsViewController *settings = [DYLikeSettingsViewController new];
        settings.overrideUserInterfaceStyle = DYLikeUserInterfaceStyle();
        if (top.navigationController) {
            [top.navigationController pushViewController:settings animated:YES];
        } else {
            UINavigationController *navigation = [[UINavigationController alloc] initWithRootViewController:settings];
            settings.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc]
                initWithBarButtonSystemItem:UIBarButtonSystemItemClose target:settings action:@selector(closeSettings)];
            [top presentViewController:navigation animated:YES completion:nil];
        }
    });
}

static BOOL DYLikeSet(id object, NSString *key, id value) {
    @try {
        [object setValue:value forKey:key];
        return YES;
    } @catch (__unused NSException *exception) {
        return NO;
    }
}

void DYLikeInstallSettingsHook(void) {
    static BOOL installed;
    if (installed) return;
    Class cls = NSClassFromString(@"AWESettingsViewModel");
    Class itemClass = NSClassFromString(@"AWESettingItemModel");
    Class sectionClass = NSClassFromString(@"AWESettingSectionModel");
    SEL selector = NSSelectorFromString(@"sectionDataArray");
    Method method = class_getInstanceMethod(cls, selector);
    if (!method || !itemClass || !sectionClass) return;
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (signature.numberOfArguments != 2 || signature.methodReturnType[0] != '@') return;

    IMP original = method_getImplementation(method);
    IMP replacement = imp_implementationWithBlock(^id(id owner) {
        id value = ((id (*)(id, SEL))original)(owner, selector);
        if (![value isKindOfClass:NSArray.class]) return value;
        for (id section in value) {
            id items = DYLikeRead(section, @"itemArray");
            if (![items isKindOfClass:NSArray.class]) continue;
            for (id item in items) {
                if ([DYLikeRead(item, @"identifier") isEqual:@"DYSecondaryConfirmation.Settings"]) return value;
            }
        }

        id item = [itemClass new];
        BOOL valid = DYLikeSet(item, @"identifier", @"DYSecondaryConfirmation.Settings");
        valid &= DYLikeSet(item, @"title", @"二次确认");
        valid &= DYLikeSet(item, @"cellType", @26);
        valid &= DYLikeSet(item, @"cellTappedBlock", ^{ DYLikeOpenSettings(); });
        DYLikeSet(item, @"detail", DYLikeVersion);
        DYLikeSet(item, @"isEnable", @YES);
        DYLikeSet(item, @"colorStyle", @2);
        DYLikeSet(item, @"svgIconImageName", @"ic_gearsimplify_outlined_20");
        DYLikeSet(item, @"specificIconImage", [UIImage systemImageNamed:@"checkmark.circle.fill"]);

        id section = [sectionClass new];
        valid &= DYLikeSet(section, @"itemArray", @[item]);
        DYLikeSet(section, @"sectionHeaderHeight", @16);
        if (!valid) return value;
        NSMutableArray *sections = [value mutableCopy];
        [sections insertObject:section atIndex:0];
        return sections;
    });
    class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
    installed = YES;
}
