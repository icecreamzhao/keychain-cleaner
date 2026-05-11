#import <Preferences/Preferences.h>
#import <UIKit/UIKit.h>
#import <spawn.h>

extern char **environ;

#define WORK_DIR "/var/jb/var/keychain_cleaner"
#define TRIGGER_FILE WORK_DIR "/trigger"
#define RESULT_FILE WORK_DIR "/result"
#define APPS_DIR "/var/containers/Bundle/Application"

@interface KCRootListController : PSListController {
    NSMutableArray *_appList;
}
@end

@implementation KCRootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _appList = [NSMutableArray array];
        [self scanInstalledApps];
        _specifiers = [self buildSpecifiers];
    }
    return _specifiers;
}

- (void)scanInstalledApps {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *uuids = [fm contentsOfDirectoryAtPath:@"/var/containers/Bundle/Application" error:nil];
    
    for (NSString *uuid in uuids) {
        NSString *appDir = [@"/var/containers/Bundle/Application" stringByAppendingPathComponent:uuid];
        NSArray *contents = [fm contentsOfDirectoryAtPath:appDir error:nil];
        
        for (NSString *item in contents) {
            if (![item hasSuffix:@".app"]) continue;
            
            NSString *infoPath = [appDir stringByAppendingPathComponent:
                [item stringByAppendingPathComponent:@"Info.plist"]];
            NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:infoPath];
            
            NSString *bundleId = info[@"CFBundleIdentifier"];
            if (!bundleId) continue;
            
            // Skip system apps
            if ([bundleId hasPrefix:@"com.apple."]) continue;
            
            NSString *name = info[@"CFBundleDisplayName"] 
                ?: info[@"CFBundleName"] 
                ?: bundleId;
            
            [_appList addObject:@{
                @"bundleId": bundleId,
                @"name": name,
                @"version": info[@"CFBundleShortVersionString"] ?: @"?"
            }];
            break;
        }
    }
    
    [_appList sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [a[@"name"] compare:b[@"name"] options:NSCaseInsensitiveSearch];
    }];
}

- (NSMutableArray *)buildSpecifiers {
    NSMutableArray *specs = [NSMutableArray array];
    
    PSSpecifier *titleSpec = [PSSpecifier groupSpecifierWithName:
        [NSString stringWithFormat:@"已安装 App (%lu) - 点击清除 Keychain", (unsigned long)_appList.count]];
    [specs addObject:titleSpec];
    
    for (NSDictionary *app in _appList) {
        NSString *bundleId = app[@"bundleId"];
        NSString *name = app[@"name"];
        
        // App name as button (tap to clear)
        PSSpecifier *btnSpec = [PSSpecifier preferenceSpecifierNamed:name
            target:self set:NULL get:NULL
            detail:Nil cell:PSButtonCell edit:Nil];
        btnSpec->action = @selector(tapApp:);
        [btnSpec setProperty:bundleId forKey:@"bundleId"];
        [btnSpec setProperty:name forKey:@"appName"];
        [btnSpec setProperty:[NSString stringWithFormat:@"%@ (%@)", name, bundleId] 
                      forKey:@"subtitle"];
        [specs addObject:btnSpec];
    }
    
    if (_appList.count == 0) {
        PSSpecifier *emptySpec = [PSSpecifier groupSpecifierWithName:@"未找到第三方 App"];
        [specs addObject:emptySpec];
    }
    
    return specs;
}

- (void)tapApp:(PSSpecifier *)spec {
    NSString *bundleId = [spec propertyForKey:@"bundleId"];
    NSString *appName = [spec propertyForKey:@"appName"];
    
    if (!bundleId) return;
    
    // Confirmation alert
    UIAlertController *confirm = [UIAlertController 
        alertControllerWithTitle:@"清除 Keychain" 
        message:[NSString stringWithFormat:@"确认清除 %@ 的 Keychain？\n\nBundle ID: %@\n\n清除后 App 可能需要重新登录。", appName, bundleId]
        preferredStyle:UIAlertControllerStyleAlert];
    
    [confirm addAction:[UIAlertAction actionWithTitle:@"取消" 
        style:UIAlertActionStyleCancel handler:nil]];
    [confirm addAction:[UIAlertAction actionWithTitle:@"确认清除" 
        style:UIAlertActionStyleDestructive handler:^(UIAlertAction *_) {
            [self doClear:bundleId appName:appName];
        }]];
    
    [self presentViewController:confirm animated:YES completion:nil];
}

- (void)doClear:(NSString *)bundleId appName:(NSString *)appName {
    unlink(RESULT_FILE);
    unlink(TRIGGER_FILE);
    
    pid_t pid;
    const char *args[] = {
        "/cores/binpack/bin/sh", "-c",
        [[NSString stringWithFormat:
            @"mkdir -p " WORK_DIR " && printf %%s %@ > " TRIGGER_FILE, bundleId] UTF8String],
        NULL
    };
    
    int ret = posix_spawn(&pid, "/cores/binpack/bin/sh", NULL, NULL, 
                          (char *const *)args, environ);
    if (ret != 0) {
        [self showAlert:@"失败" msg:[NSString stringWithFormat:
            @"无法创建触发文件 (err=%d)", ret]];
        return;
    }
    waitpid(pid, NULL, 0);
    
    [self showAlert:@"处理中" msg:[NSString stringWithFormat:
        @"正在清除 %@ 的 Keychain...", appName]];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC),
        dispatch_get_main_queue(), ^{ [self pollResult]; });
}

- (void)pollResult {
    NSString *result = [NSString stringWithContentsOfFile:@RESULT_FILE 
                                                  encoding:NSUTF8StringEncoding error:nil];
    if (result) {
        [self dismissViewControllerAnimated:NO completion:^{
            [self showAlert:@"Keychain 清理结果" msg:result];
        }];
    } else {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
            dispatch_get_main_queue(), ^{ [self pollResult]; });
    }
}

- (void)showAlert:(NSString *)title msg:(NSString *)msg {
    UIAlertController *alert = [UIAlertController 
        alertControllerWithTitle:title message:msg 
        preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"好" 
        style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
