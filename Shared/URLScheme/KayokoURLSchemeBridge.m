//
//  KayokoURLSchemeBridge.m
//  Kayoko
//

#import "KayokoURLSchemeBridge.h"
#import "KayokoURLSchemeProtocol.h"

#import <notify.h>

static const NSTimeInterval kKayokoURLSchemeBridgeResponseTimeout = 5.0;

@implementation KayokoURLSchemeBridge

#pragma mark - Lifecycle

+ (instancetype)sharedBridge {
    static KayokoURLSchemeBridge *bridge;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      bridge = [[self alloc] init];
    });
    return bridge;
}

#pragma mark - Requests

- (BOOL)sendURL:(NSURL *)URL source:(NSString *)source error:(NSError **)error {
    if (!KayokoURLSchemeIsKayokoURL(URL)) {
        if (error) {
            *error = KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeTransportFailure,
                                              @"Not a kayoko:// URL");
        }
        return NO;
    }

    NSString *requestIdentifier = [[NSUUID UUID] UUIDString];
    NSString *requestPath = KayokoURLSchemeRequestPath();
    NSString *responsePath = KayokoURLSchemeResponsePath();

    __block NSDictionary<NSString *, id> *response = nil;
    dispatch_semaphore_t received = dispatch_semaphore_create(0);
    int token = -1;
    NSError *failure = nil;
    BOOL handled = NO;

    do {
        uint32_t status = notify_register_dispatch(
            [kKayokoURLSchemeResponseNotificationName UTF8String], &token,
            dispatch_queue_create("com.mlgm.kayoko.url-scheme.response", DISPATCH_QUEUE_SERIAL),
            ^(int notificationToken) {
              (void)notificationToken;
              NSDictionary<NSString *, id> *message = KayokoURLSchemeReadMessage(responsePath);
              if ([message[kKayokoURLSchemeMessageKeyRequestIdentifier] isEqual:requestIdentifier]) {
                  response = message;
                  dispatch_semaphore_signal(received);
              }
            });
        if (status != NOTIFY_STATUS_OK) {
            token = -1;
            failure = KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeTransportFailure,
                                               @"Unable to register URL scheme response observer");
            break;
        }

        NSMutableDictionary<NSString *, id> *request = [NSMutableDictionary dictionary];
        [request setObject:requestIdentifier forKey:kKayokoURLSchemeMessageKeyRequestIdentifier];
        [request setObject:[URL absoluteString] ?: @"" forKey:kKayokoURLSchemeMessageKeyURL];
        if ([source length] > 0) {
            [request setObject:source forKey:kKayokoURLSchemeMessageKeySource];
        }

        NSError *writeError = nil;
        if (!KayokoURLSchemeWriteMessage(request, requestPath, &writeError)) {
            failure = writeError ?: KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeTransportFailure,
                                                            @"Unable to write URL scheme request");
            break;
        }

        status = notify_post([kKayokoURLSchemeRequestNotificationName UTF8String]);
        if (status != NOTIFY_STATUS_OK) {
            failure = KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeTransportFailure,
                                               @"Unable to post URL scheme request");
            break;
        }

        if (dispatch_semaphore_wait(received,
                                    dispatch_time(DISPATCH_TIME_NOW,
                                                  (int64_t)(kKayokoURLSchemeBridgeResponseTimeout * NSEC_PER_SEC))) != 0) {
            failure = KayokoURLSchemeMakeError(KayokoURLSchemeErrorCodeTimedOut,
                                               @"Timed out waiting for Kayoko to handle the URL");
            break;
        }

        NSDictionary<NSString *, id> *remoteError = response[kKayokoURLSchemeMessageKeyError];
        if ([remoteError isKindOfClass:[NSDictionary class]]) {
            NSString *domain = remoteError[kKayokoURLSchemeMessageKeyErrorDomain];
            NSString *message = remoteError[kKayokoURLSchemeMessageKeyErrorMessage];
            NSInteger code = [remoteError[kKayokoURLSchemeMessageKeyErrorCode] integerValue];
            failure = [NSError errorWithDomain:([domain isKindOfClass:[NSString class]] && [domain length] > 0)
                                                       ? domain
                                                       : kKayokoURLSchemeErrorDomain
                                           code:code
                                       userInfo:@{NSLocalizedDescriptionKey : ([message isKindOfClass:[NSString class]]
                                                                                   ? message
                                                                                   : @"Kayoko rejected the URL")}];
            break;
        }

        handled = [response[kKayokoURLSchemeMessageKeyHandled] boolValue];
    } while (NO);

    if (token != -1) {
        notify_cancel(token);
    }

    NSFileManager *fileManager = [NSFileManager defaultManager];
    for (NSString *path in @[ requestPath, responsePath ]) {
        NSDictionary<NSString *, id> *message = KayokoURLSchemeReadMessage(path);
        if ([[message[kKayokoURLSchemeMessageKeyRequestIdentifier] description] isEqual:requestIdentifier]) {
            [fileManager removeItemAtPath:path error:nil];
        }
    }

    if (error) {
        *error = failure;
    }
    return handled;
}

@end
