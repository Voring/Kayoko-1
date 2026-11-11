# Kayoko

Feature-rich clipboard manager for iOS.

A Kayoko fork maintained by **mlgm**, based on the [OwnGoal Studio edition](https://github.com/OwnGoalStudio/Kayoko).

## URL Scheme

本分支新增 `kayoko://` URL scheme，方便其他插件 / 快捷指令 / 脚本唤起 Kayoko。

### 支持的动作

| URL | 说明 |
| --- | --- |
| `kayoko://show` | 打开面板（与手动唤起一致，默认使用「初始视图」设置） |
| `kayoko://show?view=favorites` | 打开面板并停留在收藏页，`view=history` 为历史页 |
| `kayoko://show?q=关键词` | 打开面板并直接以该关键词搜索 |
| `kayoko://favorites` | 等价于 `show?view=favorites` |
| `kayoko://search?q=关键词` | 打开面板并搜索，`q` 必填 |
| `kayoko://hide` | 收起面板 |
| `kayoko://toggle` | 已显示则收起，否则打开 |
| `kayoko://clear?target=history` | 清空历史 / `favorites` 清空收藏 / `all` 全部清空 |
| `kayoko://reload` | 重新加载历史列表（外部导入数据后可用） |
| `kayoko://add?text=内容` | 把内容写入剪贴板并记录进历史 |
| `kayoko://add?text=内容&paste=1` | 写入后按「自动粘贴」设置直接粘贴 |
| `kayoko://copy?index=0` | 复制历史中第 `index` 条（0 为最新） |
| `kayoko://paste?index=0` | 复制并触发粘贴（遵循「自动粘贴」设置） |
| `kayoko://copy?source=favorites&index=0` | 从收藏页取第 `index` 条 |

公共参数：

- `x-success` / `x-error`：动作完成后由 Kayoko 打开的回调 URL（`kayoko://` 自身的回调会被忽略，避免递归）。
- `bundle`（仅 `add`）：写入历史时记录的来源 App bundle id，默认取当前键盘宿主 App。
- 参数值请自行做 URL 编码（中文、空格、`&`、`%` 等）。`kayoko://add?text=hello%20world` 这类写法最稳妥。

### 在其他插件里调用

SpringBoard 内的插件可以直接调用导出的 C 函数（无需任何 IPC）：

```objc
#import <UIKit/UIKit.h>

BOOL handled = KayokoURLSchemeHandleURL([NSURL URLWithString:@"kayoko://show?view=favorites"], @"MyTweak")
```

或通过 `openURL`（KayokoCore 已在 SpringBoard 内接管 `-[UIApplication openURL:...]` 与
`-[SpringBoard application:openURL:options:]`）：

```objc
[[UIApplication sharedApplication] openURL:[NSURL URLWithString:@"kayoko://search?q=hello"]
                                   options:@{}
                         completionHandler:nil];
```

Kayoko 未编译进调用方时，可用运行时查找符号：

```objc
typedef BOOL (*KayokoHandleURLFunction)(NSURL *, NSString *);
KayokoHandleURLFunction function = (KayokoHandleURLFunction)dlsym(RTLD_DEFAULT, "KayokoURLSchemeHandleURL");
if (function) {
    function([NSURL URLWithString:@"kayoko://toggle"], @"MyTweak");
}
```

运行在普通 App 进程里的插件，KayokoHelper 会拦截 `-[UIApplication openURL:options:completionHandler:]`、
`-[UIApplication openURL:]` 以及 `LSApplicationWorkspace` 的 `openURL:withOptions:` /
`openSensitiveURL:withOptions:`，把 `kayoko://` 请求写入
`/var/mobile/Library/com.mlgm.kayoko/url-scheme/request.plist` 并通知 SpringBoard 执行，再把结果回写到
`response.plist`。调用方阻塞等待响应，最长 5 秒。

### 已知限制

iOS 的 URL scheme 由 LaunchServices 解析，而本插件是注入到 SpringBoard / App 进程的 dylib，并没有向
LaunchServices 注册独立 App，因此：

- 在已注入 Kayoko 的进程内调用（其他插件、SpringBoard 内部、注入后的 App）→ 正常处理。
- 未注入 Kayoko 的 App（例如未被注入的 Safari、未覆盖到的系统组件）里点 `kayoko://` 链接 → 系统找不到
  处理者，什么都不会发生。
- App 进程内的请求依赖对 `/var/mobile/Library/com.mlgm.kayoko/url-scheme/` 的写权限；若沙盒拒绝写入，
  日志会打印 `Kayoko: URL scheme ... failed`，此时请改用 SpringBoard 侧的直调 API。

## Credits


- Original project: [AlexandraAurora/Kayoko](https://github.com/AlexandraAurora/Kayoko)
- Based on: [OwnGoalStudio/Kayoko](https://github.com/OwnGoalStudio/Kayoko)

## License

GPLv3. See [`COPYING`](COPYING).
