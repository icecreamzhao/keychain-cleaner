# Keychain Cleaner

越狱 iOS (palera1n rootless) 下清除指定 App Keychain 数据的工具。

通过 iOS 设置面板一键操作，无需终端。

## 功能

- 自动扫描已安装第三方 App 列表
- 一键清除选中 App 的 Keychain (genp/inet/cert/keys)
- Settings 面板集成，点击即用

## 安装

依赖：palera1n rootless + preferenceloader + sqlite3

```bash
git clone git@github.com:icecreamzhao/keychain-cleaner.git
cd keychain-cleaner
export PATH=$HOME/bin:$PATH
make clean && make
```

部署文件到 `/var/jb/` 对应路径，加载 launchd daemon，killall Preferences。

## 工作原理

```
Settings 点击 App → posix_spawn 写 trigger 文件
→ launchd WatchPaths 触发 shell 脚本
→ 脚本: unload securityd → chmod/sqlite3 DELETE → load securityd
→ 写 result 文件 → PreferenceBundle 轮询 → Alert 弹窗显示
```

## 技术要点

- **securityd 锁**: Keychain DB 被 securityd WAL 锁定，需先 `launchctl unload`
- **C daemon 替代**: C daemon 调用 system()/posix_spawn 会被 kernel 杀，改用 shell 脚本
- **IPC**: Settings.app 沙箱通过 posix_spawn 写文件到 `/var/jb/var/keychain_cleaner/`
- **DB 路径**: `/private/var/Keychains/keychain-2.db`，表: genp/inet/cert/keys，按 agrp 匹配

## 项目结构

```
├── Makefile                     # Theos (tool + bundle)
├── KCRootListController.m       # 设置面板 (PSListController)
├── daemon/
│   ├── keychain_clear.sh        # Shell 脚本 (核心)
│   ├── keychain_cleanerd.c      # C daemon (废弃)
│   └── com.hermes.keychaincleaner.plist  # launchd
├── Resources/{Info,Root}.plist  # Bundle 配置
└── control / entry.plist        # 打包信息
```

## License

MIT
