#import "../Core/DYLikeCore.h"
#import "../Settings/DYLikeSettings.h"
#import "../UI/DYLikePrompt.h"
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <stdatomic.h>
#import <string.h>

typedef NS_ENUM(NSUInteger, DYShape) {
    DYShapeV, DYShapeO, DYShapeOO, DYShapeOOO, DYShapeOOOO, DYShapeOOOOO, DYShapeOOOOOOO,
    DYShapeB, DYShapeQ, DYShapeS, DYShapeP, DYShapeBO, DYShapeBOBO, DYShapeOOBO,
    DYShapeOBO, DYShapeOOQO, DYShapeOQQO, DYShapeF7, DYShapeF9, DYShapeF11,
    DYShapeOOOIOO, DYShapeOOOIBOO, DYShapeOOOIOOOO, DYShapeOOOOOIBOOO
};
typedef struct {
    const char *className;
    const char *selectorName;
    DYShape shape;
    DYLikeActionType action;
    DYLikeIntent intent;
    NSInteger subject;
    NSInteger completion;
} DYHook;

static const DYHook DYHooks[] = {
#define DY_HOOK(cls, sel, shape, action, intent, subject, completion) \
    {cls, sel, DYShape##shape, DYLikeAction##action, DYLikeIntent##intent, subject, completion},
#include "DYLikeHookList.inc"
#undef DY_HOOK
};

static const char *DYShapeTypes(DYShape shape) {
    switch (shape) {
        case DYShapeV: return "";
        case DYShapeO: return "@";
        case DYShapeOO: return "@@";
        case DYShapeOOO: return "@@@";
        case DYShapeOOOO: return "@@@@";
        case DYShapeOOOOO: return "@@@@@";
        case DYShapeOOOOOOO: return "@@@@@@@";
        case DYShapeB: return "B";
        case DYShapeQ: return "Q";
        case DYShapeS: return "q";
        case DYShapeP: return "P";
        case DYShapeBO: return "B@";
        case DYShapeBOBO: return "B@B@";
        case DYShapeOOBO: return "@@B@";
        case DYShapeOBO: return "@B@";
        case DYShapeOOQO: return "@@Q@";
        case DYShapeOQQO: return "@QQ@";
        case DYShapeF7: return "@@@@@@d";
        case DYShapeF9: return "@@@@@@dB@";
        case DYShapeF11: return "@@@@@@@dB@B";
        case DYShapeOOOIOO: return "@@@i@@";
        case DYShapeOOOIBOO: return "@@@iB@@";
        case DYShapeOOOIOOOO: return "@@@i@@@@";
        case DYShapeOOOOOIBOOO: return "@@@@@iB@@@";
    }
    return NULL;
}

static BOOL DYMatches(Method method, DYShape shape) {
    if (!method) return NO;
    const char *types = DYShapeTypes(shape);
    NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
    if (!types || signature.methodReturnType[0] != 'v' || signature.numberOfArguments != strlen(types) + 2) return NO;
    for (NSUInteger i = 0; types[i]; i++) {
        const char *actual = [signature getArgumentTypeAtIndex:i + 2];
        if (types[i] == 'P') {
            if (strcmp(actual, @encode(CGPoint)) != 0) return NO;
        } else if (actual[0] != types[i]) return NO;
    }
    return YES;
}

static BOOL DYIsBlock(id object) {
    Class cls = NSClassFromString(@"NSBlock");
    return cls && [object isKindOfClass:cls];
}

// 保存延迟执行的参数，并复制栈上的回调。
static id DYBox(id object) {
    return DYIsBlock(object) ? [object copy] : object ?: NSNull.null;
}
static id DYArg(NSArray *arguments, NSInteger index) {
    if (index < 0 || index >= (NSInteger)arguments.count) return nil;
    return arguments[index] == NSNull.null ? nil : arguments[index];
}

struct DYBlockLayout {
    void *isa;
    int flags;
    int reserved;
    void (*invoke)(void *, ...);
    void *descriptor;
};
// 读取回调签名，供取消操作时校验参数类型。
static NSMethodSignature *DYBlockSignature(id block) {
    if (!DYIsBlock(block)) return nil;
    struct DYBlockLayout *layout = (__bridge void *)block;
    if (!(layout->flags & (1 << 30))) return nil;
    uint8_t *descriptor = (uint8_t *)layout->descriptor + 2 * sizeof(unsigned long);
    if (layout->flags & (1 << 25)) descriptor += 2 * sizeof(void *);
    const char *signature = *(const char **)descriptor;
    return signature ? [NSMethodSignature signatureWithObjCTypes:signature] : nil;
}

// 按回调参数类型返回取消结果。
static dispatch_block_t DYCancelHandler(id callback, const DYHook *hook, id subject) {
    NSMethodSignature *signature = DYBlockSignature(callback);
    if (!signature || signature.methodReturnType[0] != 'v') return nil;
    NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled
        userInfo:@{NSLocalizedDescriptionKey: @"已取消本次操作"}];
    if (signature.numberOfArguments == 3 && [signature getArgumentTypeAtIndex:2][0] == '@') {
        if ([signature getArgumentTypeAtIndex:1][0] == '@') {
            return ^{ ((void (^)(id, NSError *))callback)(nil, error); };
        }
        if ([signature getArgumentTypeAtIndex:1][0] == 'B') {
            return ^{ ((void (^)(BOOL, NSError *))callback)(NO, error); };
        }
        if (hook->action == DYLikeActionFollow) {
            NSNumber *status = DYLikeRead(subject, @"followStatus") ?: DYLikeRead(DYLikeRead(subject, @"followInfo"), @"followStatus");
            long long previous = [status isKindOfClass:NSNumber.class] ? status.longLongValue :
                (hook->intent == DYLikeIntentRemove ? 1 : 0);
            switch ([signature getArgumentTypeAtIndex:1][0]) {
                case 'q': return ^{ ((void (^)(long long, NSError *))callback)(previous, error); };
                case 'Q': return ^{ ((void (^)(unsigned long long, NSError *))callback)((unsigned long long)previous, error); };
                case 'i': return ^{ ((void (^)(int, NSError *))callback)((int)previous, error); };
                case 'I': return ^{ ((void (^)(unsigned int, NSError *))callback)((unsigned int)previous, error); };
            }
        }
    }
    return nil;
}

// 根据已确认的入口选择取消关注执行方法。
static dispatch_block_t DYUnfollowOperation(const DYHook *hook, id owner, NSArray *arguments) {
    if (hook->action != DYLikeActionFollow || hook->intent == DYLikeIntentAdd) return nil;
    if (strcmp(hook->className, "AWEProfileFollowAreaFollowComponent") == 0 &&
        strcmp(hook->selectorName, "handleFollowEventWithHeaderContext:enterMethod:fromTopButton:completion:") == 0) {
        SEL selector = NSSelectorFromString(@"handleUnfollowEventWithHeaderContext:fromRemoveMate:completion:");
        if (!DYMatches(class_getInstanceMethod([owner class], selector), DYShapeOBO)) return nil;
        id context = DYArg(arguments, 0);
        id completion = DYArg(arguments, 3);
        return ^{
            ((void (*)(id, SEL, id, BOOL, id))objc_msgSend)(owner, selector, context, NO, completion);
        };
    }
    if (strcmp(hook->className, "AWEProfileFollowAreaFollowActionCoordinator") == 0 &&
        strcmp(hook->selectorName, "p_unfollowFromRemoveMate:completion:") == 0) {
        SEL selector = NSSelectorFromString(@"p_startUnfollowFromRemoveMate:completion:");
        if (!DYMatches(class_getInstanceMethod([owner class], selector), DYShapeBO)) return nil;
        BOOL fromRemoveMate = [DYArg(arguments, 0) boolValue];
        id completion = DYArg(arguments, 1);
        return ^{
            ((void (*)(id, SEL, BOOL, id))objc_msgSend)(owner, selector, fromRemoveMate, completion);
        };
    }
    if (strcmp(hook->className, "AWEProfileHeaderFollowAreaCell") == 0 &&
        strcmp(hook->selectorName, "relationBtnClicked:") == 0) {
        id relation = DYLikeRead(owner, @"relationView");
        id machine = DYLikeRead(relation, @"relationBtnStateMachine");
        id state = DYLikeRead(machine, @"currentState");
        id context = DYLikeRead(state, @"context");
        NSString *userID = DYLikeRead(DYLikeRead(DYLikeRead(owner, @"context"), @"userModel"), @"userID");
        if (![userID isKindOfClass:NSString.class] || !userID.length ||
            ![userID isEqual:DYLikeRead(DYLikeRead(DYLikeRead(context, @"followContext"), @"user"), @"userID")]) return nil;
        SEL unfollow = NSSelectorFromString(@"unfollowUser");
        SEL doubleCheck = NSSelectorFromString(@"setEnableDoubleCheckAlert:");
        if (!DYMatches(class_getInstanceMethod([state class], unfollow), DYShapeV) ||
            !DYMatches(class_getInstanceMethod([context class], doubleCheck), DYShapeB)) return nil;
        return ^{
            if (DYLikeRead(owner, @"relationView") != relation || DYLikeRead(machine, @"currentState") != state ||
                DYLikeRead(state, @"context") != context ||
                ![userID isEqual:DYLikeRead(DYLikeRead(DYLikeRead(context, @"followContext"), @"user"), @"userID")]) {
                [DYLikePrompt showStaleNotice];
                return;
            }
            BOOL originalDoubleCheck = [DYLikeRead(context, @"enableDoubleCheckAlert") boolValue];
            ((void (*)(id, SEL, BOOL))objc_msgSend)(context, doubleCheck, NO);
            @try {
                ((void (*)(id, SEL))objc_msgSend)(state, unfollow);
            } @finally {
                ((void (*)(id, SEL, BOOL))objc_msgSend)(context, doubleCheck, originalDoubleCheck);
            }
        };
    }
    if (strcmp(hook->className, "IESLiveUserCardStore") == 0 &&
        strcmp(hook->selectorName, "actionUnFollow:") == 0) {
        SEL selector = NSSelectorFromString(@"unfollowUser");
        if (!DYMatches(class_getInstanceMethod([owner class], selector), DYShapeV)) return nil;
        return ^{ ((void (*)(id, SEL))objc_msgSend)(owner, selector); };
    }
    if (strcmp(hook->className, "IESLiveUserCardFollowButton") == 0 &&
        strcmp(hook->selectorName, "cancelFollow") == 0) {
        id store = DYLikeRead(owner, @"store");
        SEL selector = NSSelectorFromString(@"unfollowUser");
        if (!DYMatches(class_getInstanceMethod([store class], selector), DYShapeV)) return nil;
        return ^{
            if (DYLikeRead(owner, @"store") != store) {
                [DYLikePrompt showStaleNotice];
                return;
            }
            ((void (*)(id, SEL))objc_msgSend)(store, selector);
        };
    }
    return nil;
}

static void DYGate(const DYHook *hook, id owner, NSArray *arguments, dispatch_block_t operation) {
    id subject = DYArg(arguments, hook->subject);
    if (!DYLikeEnabled(hook->action)) {
        operation();
        return;
    }
    dispatch_block_t confirmedUnfollow = DYUnfollowOperation(hook, owner, arguments);
    if (DYLikeIsReplaying(hook->action)) {
        DYLikeGuard(hook->action, hook->intent, owner, subject, operation, nil, confirmedUnfollow);
        return;
    }
    id callback = hook->completion == -2 ? DYLikeRead(subject, @"completionBlock") : DYArg(arguments, hook->completion);
    dispatch_block_t cancellation = callback ? DYCancelHandler(callback, hook, subject) : nil;
    if (callback && !cancellation) {
        NSLog(@"[DYSecondaryConfirmation] Unsupported completion: %s %s", hook->className, hook->selectorName);
    }
    DYLikeGuard(hook->action, hook->intent, owner, subject, operation, cancellation, confirmedUnfollow);
}

// 按原方法签名生成拦截函数。
static IMP DYReplacement(const DYHook *hook, SEL selector, IMP original) {
#define ARG(n) DYArg(args, n)
#define GATE(...) DYGate(hook, owner, args, ^{ __VA_ARGS__; })
    switch (hook->shape) {
        case DYShapeV: return imp_implementationWithBlock(^(id owner) {
            NSArray *args = @[];
            GATE(((void (*)(id, SEL))original)(owner, selector));
        });
        case DYShapeO: return imp_implementationWithBlock(^(id owner, id a) {
            NSArray *args = @[DYBox(a)];
            GATE(((void (*)(id, SEL, id))original)(owner, selector, ARG(0)));
        });
        case DYShapeOO: return imp_implementationWithBlock(^(id owner, id a, id b) {
            NSArray *args = @[DYBox(a), DYBox(b)];
            GATE(((void (*)(id, SEL, id, id))original)(owner, selector, ARG(0), ARG(1)));
        });
        case DYShapeOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c)];
            GATE(((void (*)(id, SEL, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2)));
        });
        case DYShapeOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), DYBox(d)];
            GATE(((void (*)(id, SEL, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3)));
        });
        case DYShapeOOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), DYBox(d), DYBox(e)];
            GATE(((void (*)(id, SEL, id, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4)));
        });
        case DYShapeOOOOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, id g) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), DYBox(d), DYBox(e), DYBox(f), DYBox(g)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), ARG(6)));
        });
        case DYShapeOOOIOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, int secret, id e, id f) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), @(secret), DYBox(e), DYBox(f)];
            GATE(((void (*)(id, SEL, id, id, id, int, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), secret, ARG(4), ARG(5)));
        });
        case DYShapeOOOIBOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, int secret, BOOL fifa, id f, id g) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), @(secret), @(fifa), DYBox(f), DYBox(g)];
            GATE(((void (*)(id, SEL, id, id, id, int, BOOL, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), secret, fifa, ARG(5), ARG(6)));
        });
        case DYShapeOOOIOOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, int secret, id e, id f, id g, id h) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), @(secret), DYBox(e), DYBox(f), DYBox(g), DYBox(h)];
            GATE(((void (*)(id, SEL, id, id, id, int, id, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), secret, ARG(4), ARG(5), ARG(6), ARG(7)));
        });
        case DYShapeOOOOOIBOOO: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, int secret, BOOL fifa, id h, id i, id j) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), DYBox(d), DYBox(e), @(secret), @(fifa), DYBox(h), DYBox(i), DYBox(j)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, int, BOOL, id, id, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), secret, fifa, ARG(7), ARG(8), ARG(9)));
        });
        case DYShapeB: return imp_implementationWithBlock(^(id owner, BOOL a) {
            NSArray *args = @[@(a)];
            GATE(((void (*)(id, SEL, BOOL))original)(owner, selector, a));
        });
        case DYShapeQ: return imp_implementationWithBlock(^(id owner, unsigned long long a) {
            NSArray *args = @[@(a)];
            GATE(((void (*)(id, SEL, unsigned long long))original)(owner, selector, a));
        });
        case DYShapeS: return imp_implementationWithBlock(^(id owner, long long a) {
            NSArray *args = @[@(a)];
            GATE(((void (*)(id, SEL, long long))original)(owner, selector, a));
        });
        case DYShapeP: return imp_implementationWithBlock(^(id owner, CGPoint a) {
            NSArray *args = @[];
            GATE(((void (*)(id, SEL, CGPoint))original)(owner, selector, a));
        });
        case DYShapeBO: return imp_implementationWithBlock(^(id owner, BOOL a, id b) {
            NSArray *args = @[@(a), DYBox(b)];
            GATE(((void (*)(id, SEL, BOOL, id))original)(owner, selector, a, ARG(1)));
        });
        case DYShapeBOBO: return imp_implementationWithBlock(^(id owner, BOOL a, id b, BOOL c, id d) {
            NSArray *args = @[@(a), DYBox(b), @(c), DYBox(d)];
            GATE(((void (*)(id, SEL, BOOL, id, BOOL, id))original)(owner, selector, a, ARG(1), c, ARG(3)));
        });
        case DYShapeOOBO: return imp_implementationWithBlock(^(id owner, id a, id b, BOOL c, id d) {
            NSArray *args = @[DYBox(a), DYBox(b), @(c), DYBox(d)];
            GATE(((void (*)(id, SEL, id, id, BOOL, id))original)(owner, selector, ARG(0), ARG(1), c, ARG(3)));
        });
        case DYShapeOBO: return imp_implementationWithBlock(^(id owner, id a, BOOL b, id c) {
            NSArray *args = @[DYBox(a), @(b), DYBox(c)];
            GATE(((void (*)(id, SEL, id, BOOL, id))original)(owner, selector, ARG(0), b, ARG(2)));
        });
        case DYShapeOOQO: return imp_implementationWithBlock(^(id owner, id a, id b, unsigned long long c, id d) {
            NSArray *args = @[DYBox(a), DYBox(b), @(c), DYBox(d)];
            GATE(((void (*)(id, SEL, id, id, unsigned long long, id))original)(owner, selector, ARG(0), ARG(1), c, ARG(3)));
        });
        case DYShapeOQQO: return imp_implementationWithBlock(^(id owner, id a, unsigned long long b, unsigned long long c, id d) {
            NSArray *args = @[DYBox(a), @(b), @(c), DYBox(d)];
            GATE(((void (*)(id, SEL, id, unsigned long long, unsigned long long, id))original)(owner, selector, ARG(0), b, c, ARG(3)));
        });
        case DYShapeF7: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, double padding) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), DYBox(d), DYBox(e), DYBox(f), @(padding)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, double))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), padding));
        });
        case DYShapeF9: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, double padding, BOOL force, id view) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), DYBox(d), DYBox(e), DYBox(f), @(padding), @(force), DYBox(view)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, double, BOOL, id))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), padding, force, ARG(8)));
        });
        case DYShapeF11: return imp_implementationWithBlock(^(id owner, id a, id b, id c, id d, id e, id f, id g, double padding, BOOL force, id view, BOOL block) {
            NSArray *args = @[DYBox(a), DYBox(b), DYBox(c), DYBox(d), DYBox(e), DYBox(f), DYBox(g), @(padding), @(force), DYBox(view), @(block)];
            GATE(((void (*)(id, SEL, id, id, id, id, id, id, id, double, BOOL, id, BOOL))original)(owner, selector, ARG(0), ARG(1), ARG(2), ARG(3), ARG(4), ARG(5), ARG(6), padding, force, ARG(9), block));
        });
    }
#undef GATE
#undef ARG
    return NULL;
}

static BOOL DYFeedAction(id button, DYLikeActionType *action) {
    for (NSString *key in @[@"accessibilityLabel", @"accessibilityIdentifier", @"imageNameString"]) {
        id text = DYLikeRead(button, key);
        if (![text isKindOfClass:NSString.class]) continue;
        NSString *lower = [text lowercaseString];
        if ([text containsString:@"收藏"] || [lower containsString:@"favorite"] || [lower containsString:@"collect"]) {
            *action = DYLikeActionFavorite; return YES;
        }
        if ([text containsString:@"点赞"] || [lower containsString:@"digg"] || [lower containsString:@"icon_like"]) {
            *action = DYLikeActionLike; return YES;
        }
    }
    return NO;
}

static void DYInstallFeedButtonHook(void) {
    static BOOL installed[2];
    NSArray *classes = @[@"AWEFeedVideoButton", @"AWEFeedRelatedVideoCardInteractionButton"];
    for (NSUInteger index = 0; index < classes.count; index++) {
        if (installed[index]) continue;
        Class cls = NSClassFromString(classes[index]);
        SEL selector = NSSelectorFromString(@"touchUpInsideBlock");
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        NSMethodSignature *signature = [NSMethodSignature signatureWithObjCTypes:method_getTypeEncoding(method)];
        if (signature.methodReturnType[0] != '@' || signature.numberOfArguments != 2) continue;
        IMP original = method_getImplementation(method);
        IMP replacement = imp_implementationWithBlock(^id(id owner) {
            id callback = ((id (*)(id, SEL))original)(owner, selector);
            NSMethodSignature *blockSignature = DYBlockSignature(callback);
            if (!blockSignature || blockSignature.methodReturnType[0] != 'v' || blockSignature.numberOfArguments != 1) return callback;
            dispatch_block_t block = [callback copy];
            __weak id weakOwner = owner;
            return [^{
                id button = weakOwner;
                if (!button) return;
                DYLikeActionType action;
                if (!DYFeedAction(button, &action) || !DYLikeEnabled(action)) { block(); return; }
                DYLikeGuard(action, DYLikeIntentToggle, button, nil, ^{
                    if (((id (*)(id, SEL))original)(button, selector) != block) {
                        [DYLikePrompt showStaleNotice];
                        return;
                    }
                    block();
                }, nil, nil);
            } copy];
        });
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
        installed[index] = YES;
    }
}

static void DYInstallHooks(void) {
    static BOOL installed[sizeof(DYHooks) / sizeof(DYHooks[0])];
    NSUInteger added = 0;
    for (NSUInteger i = 0; i < sizeof(DYHooks) / sizeof(DYHooks[0]); i++) {
        if (installed[i]) continue;
        const DYHook *hook = &DYHooks[i];
        Class cls = NSClassFromString(@(hook->className));
        if (!cls) continue;
        BOOL isClassMethod = hook->selectorName[0] == '+';
        if (isClassMethod) cls = object_getClass(cls);
        SEL selector = sel_registerName(hook->selectorName + (isClassMethod ? 1 : 0));
        Method method = class_getInstanceMethod(cls, selector);
        if (!method) continue;
        if (!DYMatches(method, hook->shape)) {
            installed[i] = YES;
            NSLog(@"[DYSecondaryConfirmation] Signature mismatch: %s %s", hook->className, hook->selectorName);
            continue;
        }
        IMP replacement = DYReplacement(hook, selector, method_getImplementation(method));
        if (!replacement) continue;
        class_replaceMethod(cls, selector, replacement, method_getTypeEncoding(method));
        installed[i] = YES;
        added++;
    }
    DYInstallFeedButtonHook();
    DYLikeInstallThemeHooks();
    DYLikeInstallSettingsHook();
    if (added) NSLog(@"[DYSecondaryConfirmation] Installed %lu action hooks", (unsigned long)added);
}

static atomic_bool DYInstallScheduled;
static void DYImageLoaded(__unused const struct mach_header *header, __unused intptr_t slide) {
    if (atomic_exchange(&DYInstallScheduled, true)) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        atomic_store(&DYInstallScheduled, false);
        DYInstallHooks();
    });
}

__attribute__((constructor)) static void DYLikeStart(void) {
    @autoreleasepool {
        DYLikeEnsureDefaults();
        _dyld_register_func_for_add_image(DYImageLoaded);
    }
}
