# myssh

[![CI](https://github.com/ssugarr/myssh/actions/workflows/ci.yml/badge.svg)](https://github.com/ssugarr/myssh/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](./LICENSE)

Windows 终端里的个人 SSH 连接管理工具：保存主机、一键连接、经跳板登录；密码用 Windows DPAPI 加密保存。

> PowerShell 7 模块 + 系统 OpenSSH，无额外运行时。

## 功能

- 保存 / 列出 / 编辑 / 重命名 / 删除 SSH 连接
- `myssh <alias>` 一键登录
- **跳板登录**（`--jump` / ProxyCommand）
- 密码 DPAPI 加密存储 + 自动填密
- 远程命令：`myssh host -- uname -a`
- Tab 补全、连通性测试

## 要求

- Windows 10/11
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- 系统 OpenSSH 客户端（`ssh.exe`）

## 安装

安装后终端里多一个命令行工具 **`myssh`**（不是带窗口的独立软件）。

### 方式 A：GitHub Releases（推荐）

打开 [Releases](https://github.com/ssugarr/myssh/releases)，下载：

- **`myssh-*-win-x64.msi`** → 双击安装，重开终端  
- 或 **`myssh-*-win-x64.zip`** → 解压后双击 `Setup.cmd`

```powershell
myssh version
myssh help
```

### 方式 B：从源码

```powershell
git clone https://github.com/ssugarr/myssh.git
cd myssh
pwsh -File .\install.ps1
```

安装会写入 `%LOCALAPPDATA%\Programs\myssh`、加入用户 PATH，并注册 PowerShell 模块。

### 卸载

```powershell
# 若从源码/zip 安装
pwsh -File "$env:LOCALAPPDATA\Programs\myssh\uninstall.ps1"

# 若用 MSI 安装：设置 → 应用 → myssh → 卸载
```

配置目录 `~/.myssh/` 默认保留。要连同密码一起删：

```powershell
Remove-Item -Recurse -Force $HOME\.myssh
```

## 快速开始

```powershell
# 交互新增（默认询问密码）
myssh add

# 命令行新增
myssh add aliyun --host 1.2.3.4 --user root --no-key --password '***'

# 跳板机
myssh add jump --host bastion.example.com --user ops --no-key
myssh password jump

# 经跳板登录内网机
myssh add app --host 10.0.0.8 --user app --jump jump --no-key
myssh password app
myssh app

# 远程命令
myssh app -- hostname
```

## 常用命令

| 命令 | 说明 |
|------|------|
| `myssh add` | 新增连接 |
| `myssh list` / `myssh status` | 列表 / 总览 |
| `myssh <alias>` | 连接（含跳板） |
| `myssh password <alias>` | 保存/更新密码 |
| `myssh rename old new` | 重命名 |
| `myssh test <alias>` | 测试连通 |
| `myssh help` | 帮助 |

配置目录：`~/.myssh/`（**不会**进入 Git）。

## 安全说明

- 密码使用当前 Windows 用户的 DPAPI 加密，仅本机当前用户可解密
- 不要在命令行明文传 `--password` 后把历史提交到仓库
- 开源仓库不含任何真实主机密码

## 开发 / 测试

```powershell
pwsh -File .\tests\run-tests.ps1
# 可选：对本机已配置主机做联通测试
pwsh -File .\tests\live-tests.ps1
```

## 技术栈

- PowerShell 7 模块
- Windows OpenSSH（`ssh.exe`）
- JSON 配置
- Windows DPAPI + `SSH_ASKPASS`
- 跳板：`ProxyCommand`

## License

[MIT](./LICENSE)
