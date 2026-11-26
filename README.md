# myssh

Windows 终端里的个人 SSH 连接管理工具：保存主机、一键连接、经跳板登录，密码用 DPAPI 加密保存。

> PowerShell 7 模块 + 系统 OpenSSH，无额外运行时。

## 功能

- 保存 / 列出 / 编辑 / 重命名 / 删除 SSH 连接
- `myssh <alias>` 一键登录
- 跳板登录（`--jump`）
- 密码 DPAPI 加密存储 + 自动填密
- 执行远程命令：`myssh host -- uname -a`
- Tab 补全、连通性测试

## 要求

- Windows 10/11
- [PowerShell 7+](https://github.com/PowerShell/PowerShell)
- 系统 OpenSSH 客户端（`ssh.exe`）

## 安装

```powershell
git clone https://github.com/ssugarr/myssh.git
cd myssh
pwsh -File .\install.ps1
```

安装脚本会：

1. 把模块链接到 `~/Documents/PowerShell/Modules/myssh`
2. 将 `bin/` 加入用户 PATH
3. 在 Profile 中自动 `Import-Module myssh`

然后**重新打开终端**，执行：

```powershell
myssh status
myssh help
```

## 快速开始

```powershell
# 交互新增（默认询问密码）
myssh add

# 或命令行新增
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
| `myssh list` | 列出连接 |
| `myssh <alias>` | 连接 |
| `myssh password <alias>` | 保存/更新密码 |
| `myssh rename old new` | 重命名 |
| `myssh test <alias>` | 测试连通 |
| `myssh status` | 总览 |
| `myssh help` | 帮助 |

配置与加密密码保存在本机 `~/.myssh/`（不会进 Git）。

## 开发 / 测试

```powershell
pwsh -File .\tests\run-tests.ps1
```

## 技术栈

- PowerShell 7 模块
- Windows OpenSSH（`ssh.exe`）
- JSON 配置
- Windows DPAPI 密码存储
- `SSH_ASKPASS` 自动填密
- 跳板：`ProxyCommand`

## License

[MIT](./LICENSE)
