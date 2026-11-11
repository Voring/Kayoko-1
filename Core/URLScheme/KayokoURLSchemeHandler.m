//
//  KayokoURLSchemeHandler.m
//  Kayoko
//

#import "KayokoURLSchemeHandler.h"

#import "KayokoCoreRuntime.h"
#import "KayokoKeyboardHostResolver.h"
#import "KayokoPasteboardItem.h"
#import "KayokoPasteboardManager.h"
#import "KayokoURLSchemeProtocol.h"

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, KayokoURLSchemeAction) {
    KayokoURLSchemeActionUnknown = 0,
    KayokoURLSchemeActionShow,
    KayokoURLSchemeActionHide,
    KayokoURLSchemeActionToggle,
    KayokoURLSchemeActionSearch,
    KayokoURLSchemeActionFavorites,
    KayokoURLSchemeActionClear,
    KayokoURLSchemeActionReload,
    KayokoURLSchemeActionAdd,
    KayokoURLSchemeActionCopy,
    KayokoURLSchemeActionPaste,
};

#pragma mark - Parsing Helpers

static NSString *KayokoURLSchemeActionName(NSURL *URL) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    NSString *host = [[components host] lowercaseString];
    if ([host length] > 0) {
        return host;
    }

    NSString *path = [components path];
    if ([path length] == 0) {
        return @"";
    }

    NSMutableCharacterSet *trimSet = [NSMutableCharacterSet characterSetWithCharactersInString:@"/"];
    [trimSet formUnionWithCharacterSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSString *trimmed = [path stringByTrimmingCharactersInSet:trimSet];
    NSRange separatorRange = [trimmed rangeOfString:@"/"];
    if (separatorRange.location != NSNotFound) {
        trimmed = [trimmed substringToIndex:separatorRange.location];
    }
    return [trimmed lowercaseString];
}

static NSDictionary<NSString *, NSString *> *KayokoURLSchemeQueryParameters(NSURL *URL) {
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    NSMutableDictionary<NSString *, NSString *> *parameters = [NSMutableDictionary dictionary];
    for (NSURLQueryItem *queryItem in [components queryItems]) {
        NSString *name = [[queryItem name] lowercaseString];
        if ([name length] == 0) {
            continue;
        }
        [parameters setObject:([queryItem value] ?: @"") forKey:name];
    }
    return parameters;
}

static NSString *KayokoURLSchemeParameter(NSDictionary<NSString *, NSString *> *parameters, NSArray<NSString *> *names) {
    for (NSString *name in names) {
        NSString *value = parameters[name];
        if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
            return value;
        }
    }
    return nil;
}

static BOOL KayokoURLSchemeBooleanParameter(NSDictionary<NSString *, NSString *> *parameters, NSString *name,
                                            BOOL defaultValue) {
    NSString *value = [(parameters[name] ?: @"") lowercaseString];
    if ([value length] == 0) {
        return defaultValue;
    }
    if ([value isEqualToString:@"1"] || [value isEqualToString:@"true"] || [value isEqualToString:@"yes"] ||
        [value isEqualToString:@"on"]) {
        return YES;
    }
    if ([value isEqualToString:@"0"] || [value isEqualToString:@"false"] || [value isEqualToString:@"no"] ||
        [value isEqualToString:@"off"]) {
        return NO;
    }
    return defaultValue;
}

static NSString *KayokoURLSchemeHistoryKeyForView(NSString *view) {
    NSString *value = [(view ?: @"") lowercaseString];
    if ([value isEqualToString:@"favorites"] || [value isEqualToString:@"favorite"] || [value isEqualToString:@"fav"]) {
        return kKayokoHistoryKeyFavorites;
    }
    if ([value isEqualToString:@"history"] || [value isEqualToString:@"all"]) {
        return kKayokoHistoryKeyHistory;
    }
    return nil;
}

static KayokoURLSchemeAction KayokoURLSchemeActionForName(NSString *name) {
    if ([name length] == 0 || [name isEqualToString:@"show"] || [name isEqualToString:@"open"]) {
        return KayokoURLSchemeActionShow;
    }
    if ([name isEqualToString:@"hide"] || [name isEqualToString:@"close"] || [name isEqualToString:@"dismiss"]) {
        return KayokoURLSchemeActionHide;
    }
    if ([name isEqualToString:@"toggle"]) {
        return KayokoURLSchemeActionToggle;
    }
    if ([name isEqualToString:@"search"]) {
        return KayokoURLSchemeActionSearch;
    }
    if ([name isEqualToString:@"favorites"]) {
        return KayokoURLSchemeActionFavorites;
    }
    if ([name isEqualToString:@"clear"]) {
        return KayokoURLSchemeActionClear;
    }
    if ([name isEqualToString:@"reload"]) {
        return KayokoURLSchemeActionReload;
    }
    if ([name isEqualToString:@"add"] || [name isEqualToString:@"copy-text"] || [name isEqualToString:@"set"]) {
        return KayokoURLSchemeActionAdd;
    }
    if ([name isEqualToString:@"copy"]) {
        return KayokoURLSchemeActionCopy;
    }
    if ([name isEqualToString:@"paste"]) {
        return KayokoURLSchemeActionPaste;
    }
    return KayokoURLSchemeActionUnknown;
}

#pragma mark - Handler

@interface KayokoURLSchemeHandler ()

- (void)performURL:(NSURL *)URL source:(nullable NSString *)source completion:(nullable KayokoURLSchemeCompletion)completion;
- (void)handleShowWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                         runtime:(KayokoCoreRuntime *)runtime
                      completion:(nullable KayokoURLSchemeCompletion)completion;
- (void)handleClearWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                          runtime:(KayokoCoreRuntime *)runtime
                       completion:(nullable KayokoURLSchemeCompletion)completion;
- (void)handleAddWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                         source:(nullable NSString *)source
                     completion:(nullable KayokoURLSchemeCompletion)completion;
- (void)handleCopyWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                      shouldPaste:(BOOL)shouldPaste
                       completion:(nullable KayokoURLSchemeCompletion)completion;
- (void)finishWithResult:(KayokoURLSchemeResult)result
                   error:(nullable NSError *)error
              completion:(nullable KayokoURLSchemeCompletion)completion;
- (void)openCallbackURLFromURL:(NSURL *)URL success:(BOOL)success;

@end

@implementation KayokoURLSchemeHandler

#pragma mark - Lifecycle

+ (instancetype)sharedHandler {
    static KayokoURLSchemeHandler *handler;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      handler = [[self alloc] init];
    });
    return handler;
}

#pragma mark - Public API

- (BOOL)handleURL:(NSURL *)URL source:(NSString *)source completion:(KayokoURLSchemeCompletion)completion {
    if (!KayokoURLSchemeIsKayokoURL(URL)) {
        return NO;
    }

    __weak typeof(self) weakSelf = self;
    KayokoURLSchemeCompletion wrappedCompletion = ^(KayokoURLSchemeResult result, NSError *error) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (strongSelf) {
          [strongSelf openCallbackURLFromURL:URL success:(result == KayokoURLSchemeResultSuccess)];
      }
      if (completion) {
          completion(result, error);
      }
    };

    dispatch_block_t performBlock = ^{
      [self performURL:URL source:source completion:wrappedCompletion];
    };
    if ([NSThread isMainThread]) {
        performBlock();
    } else {
        dispatch_async(dispatch_get_main_queue(), performBlock);
    }
    return YES;
}

#pragma mark - Dispatch

- (void)performURL:(NSURL *)URL source:(NSString *)source completion:(KayokoURLSchemeCompletion)completion {
    KayokoURLSchemeAction action = KayokoURLSchemeActionForName(KayokoURLSchemeActionName(URL));
    NSDictionary<NSString *, NSString *> *parameters = KayokoURLSchemeQueryParameters(URL);

    if (action == KayokoURLSchemeActionUnknown) {
        [self finishWithResult:KayokoURLSchemeResultFailed
                          error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                         @"Unknown Kayoko URL scheme action")
                     completion:completion];
        return;
    }

    KayokoCoreRuntime *runtime = [KayokoCoreRuntime sharedRuntime];
    if (![runtime isEnabled]) {
        [self finishWithResult:KayokoURLSchemeResultFailed
                          error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                         @"Kayoko is disabled in preferences")
                     completion:completion];
        return;
    }

    switch (action) {
    case KayokoURLSchemeActionShow:
        [self handleShowWithParameters:parameters runtime:runtime completion:completion];
        return;
    case KayokoURLSchemeActionSearch: {
        NSString *searchText = KayokoURLSchemeParameter(parameters, @[ @"q", @"query", @"search", @"text" ]);
        if ([searchText length] == 0) {
            [self finishWithResult:KayokoURLSchemeResultFailed
                              error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                             @"search requires a q parameter")
                         completion:completion];
            return;
        }
        NSString *historyKey = KayokoURLSchemeHistoryKeyForView(
            KayokoURLSchemeParameter(parameters, @[ @"view", @"tab", @"source" ]));
        [runtime showWithHistoryKey:historyKey searchText:searchText];
        [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
        return;
    }
    case KayokoURLSchemeActionFavorites:
        [runtime showWithHistoryKey:kKayokoHistoryKeyFavorites searchText:nil];
        [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
        return;
    case KayokoURLSchemeActionHide:
        [runtime hideForExternalRequest];
        [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
        return;
    case KayokoURLSchemeActionToggle:
        if ([runtime panelVisible]) {
            [runtime hideForExternalRequest];
        } else {
            [runtime showWithHistoryKey:nil searchText:nil];
        }
        [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
        return;
    case KayokoURLSchemeActionClear:
        [self handleClearWithParameters:parameters runtime:runtime completion:completion];
        return;
    case KayokoURLSchemeActionReload:
        [runtime reloadHistory];
        [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
        return;
    case KayokoURLSchemeActionAdd:
        [self handleAddWithParameters:parameters source:source completion:completion];
        return;
    case KayokoURLSchemeActionCopy:
    case KayokoURLSchemeActionPaste:
        [self handleCopyWithParameters:parameters
                                 shouldPaste:(action == KayokoURLSchemeActionPaste)
                                  completion:completion];
        return;
    default:
        break;
    }

    [self finishWithResult:KayokoURLSchemeResultFailed
                      error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown, @"Unsupported action")
                 completion:completion];
}

#pragma mark - Actions

- (void)handleShowWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                         runtime:(KayokoCoreRuntime *)runtime
                      completion:(KayokoURLSchemeCompletion)completion {
    NSString *historyKey =
        KayokoURLSchemeHistoryKeyForView(KayokoURLSchemeParameter(parameters, @[ @"view", @"tab" ]));
    NSString *searchText = KayokoURLSchemeParameter(parameters, @[ @"q", @"query", @"search", @"text" ]);
    [runtime showWithHistoryKey:historyKey searchText:[searchText length] > 0 ? searchText : nil];
    [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
}

- (void)handleClearWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                          runtime:(KayokoCoreRuntime *)runtime
                       completion:(KayokoURLSchemeCompletion)completion {
    NSString *target =
        [(KayokoURLSchemeParameter(parameters, @[ @"target", @"view" ]) ?: @"history") lowercaseString];
    if ([target isEqualToString:@"history"] || [target isEqualToString:@"all"]) {
        [runtime clearHistory];
    }
    if ([target isEqualToString:@"favorites"] || [target isEqualToString:@"all"]) {
        [runtime clearFavorites];
    }
    if (![target isEqualToString:@"history"] && ![target isEqualToString:@"favorites"] &&
        ![target isEqualToString:@"all"]) {
        [self finishWithResult:KayokoURLSchemeResultFailed
                          error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown, @"Unknown clear target")
                     completion:completion];
        return;
    }
    [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
}

- (void)handleAddWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                         source:(NSString *)source
                     completion:(KayokoURLSchemeCompletion)completion {
    NSString *text = KayokoURLSchemeParameter(parameters, @[ @"text", @"q", @"content" ]);
    if ([text length] == 0) {
        [self finishWithResult:KayokoURLSchemeResultFailed
                          error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                         @"add requires a text parameter")
                     completion:completion];
        return;
    }

    NSString *bundleIdentifier = KayokoURLSchemeParameter(parameters, @[ @"bundle", @"bundle_id" ]);
    if ([bundleIdentifier length] == 0) {
        bundleIdentifier = [[[KayokoKeyboardHostResolver sharedResolver] currentKeyboardHostContext] bundleIdentifier];
    }
    if ([bundleIdentifier length] == 0) {
        bundleIdentifier = source;
    }
    if ([bundleIdentifier length] == 0) {
        bundleIdentifier = @"com.apple.springboard";
    }

    KayokoPasteboardManager *manager = [KayokoPasteboardManager sharedInstance];
    KayokoPasteboardItem *item = [[KayokoPasteboardItem alloc] initWithBundleIdentifier:bundleIdentifier
                                                                            andContent:text
                                                                        withImageNamed:nil];
    if (!item) {
        [self finishWithResult:KayokoURLSchemeResultFailed
                          error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown, @"Unable to create item")
                     completion:completion];
        return;
    }

    BOOL shouldPaste = KayokoURLSchemeBooleanParameter(parameters, @"paste", NO);
    BOOL stored = [manager addPasteboardItem:item toHistoryWithKey:kKayokoHistoryKeyHistory];
    if (shouldPaste) {
        [manager writePasteboardItem:item
                  sourceHistoryItem:item
                 fromHistoryWithKey:kKayokoHistoryKeyHistory
               allowsAutomaticPaste:YES];
    } else {
        stored = [manager copyPasteboardItemToPasteboard:item] || stored;
    }

    [self finishWithResult:(stored ? KayokoURLSchemeResultSuccess : KayokoURLSchemeResultFailed)
                      error:(stored ? nil
                                    : KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                               @"Unable to write to the pasteboard"))
                 completion:completion];
}

- (void)handleCopyWithParameters:(NSDictionary<NSString *, NSString *> *)parameters
                      shouldPaste:(BOOL)shouldPaste
                       completion:(KayokoURLSchemeCompletion)completion {
    NSString *historyKey =
        KayokoURLSchemeHistoryKeyForView(KayokoURLSchemeParameter(parameters, @[ @"source", @"view", @"tab" ]));
    if ([historyKey length] == 0) {
        historyKey = kKayokoHistoryKeyHistory;
    }

    NSString *indexValue = KayokoURLSchemeParameter(parameters, @[ @"index", @"i" ]);
    NSInteger index = [indexValue length] > 0 ? [indexValue integerValue] : 0;

    KayokoPasteboardManager *manager = [KayokoPasteboardManager sharedInstance];
    NSArray<NSDictionary<NSString *, id> *> *items = [manager getItemsFromHistoryWithKey:historyKey];
    if (index < 0 || (NSUInteger)index >= [items count]) {
        [self finishWithResult:KayokoURLSchemeResultFailed
                          error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                         @"No item at the requested index")
                     completion:completion];
        return;
    }

    KayokoPasteboardItem *item = [KayokoPasteboardItem itemFromDictionary:items[(NSUInteger)index]];
    if (!item) {
        [self finishWithResult:KayokoURLSchemeResultFailed
                          error:KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                         @"Unable to load the requested item")
                     completion:completion];
        return;
    }

    if (shouldPaste) {
        [manager writePasteboardItem:item
                  sourceHistoryItem:item
                 fromHistoryWithKey:historyKey
               allowsAutomaticPaste:YES];
        [self finishWithResult:KayokoURLSchemeResultSuccess error:nil completion:completion];
        return;
    }

    BOOL copied = [manager copyPasteboardItemToPasteboard:item];
    [self finishWithResult:(copied ? KayokoURLSchemeResultSuccess : KayokoURLSchemeResultFailed)
                      error:(copied ? nil
                                    : KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeUnknown,
                                                               @"Unable to write to the pasteboard"))
                 completion:completion];
}

#pragma mark - Callbacks

- (void)openCallbackURLFromURL:(NSURL *)URL success:(BOOL)success {
    NSString *key = success ? @"x-success" : @"x-error";
    NSURLComponents *components = [NSURLComponents componentsWithURL:URL resolvingAgainstBaseURL:NO];
    NSString *callbackString = nil;
    for (NSURLQueryItem *queryItem in [components queryItems]) {
        if ([[[queryItem name] lowercaseString] isEqualToString:key]) {
            callbackString = [queryItem value];
            break;
        }
    }

    if ([callbackString length] == 0) {
        return;
    }

    NSURL *callbackURL = [NSURL URLWithString:callbackString];
    if (!callbackURL || KayokoURLSchemeIsKayokoURL(callbackURL)) {
        return;
    }

    [[UIApplication sharedApplication] openURL:callbackURL options:@{} completionHandler:nil];
}

#pragma mark - Completion

- (void)finishWithResult:(KayokoURLSchemeResult)result
                   error:(NSError *)error
              completion:(KayokoURLSchemeCompletion)completion {
    if (!completion) {
        return;
    }

    if ([NSThread isMainThread]) {
        completion(result, error);
        return;
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      completion(result, error);
    });
}

@end

#pragma mark - C Entry Points

BOOL KayokoURLSchemeHandleURL(NSURL *URL, NSString *source) {
    return [[KayokoURLSchemeHandler sharedHandler] handleURL:URL source:source completion:nil];
}

BOOL KayokoURLSchemeInterceptOpenURL(NSURL *URL, KayokoURLSchemeOpenCompletion completionHandler) {
    if (!KayokoURLSchemeIsKayokoURL(URL)) {
        return NO;
    }

    [[KayokoURLSchemeHandler sharedHandler]
        handleURL:URL
          source:@"open-url"
      completion:^(KayokoURLSchemeResult result, NSError *error) {
        (void)error;
        if (completionHandler) {
            completionHandler(result == KayokoURLSchemeResultSuccess);
        }
      }];
    return YES;
}
